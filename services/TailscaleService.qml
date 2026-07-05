pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
    id: root

    // --- connection state ---
    property string backendState: ""            // Running | Stopped | Starting | NeedsLogin | NoState | NoDaemon
    readonly property bool isRunning: backendState === "Running"
    readonly property bool needsLogin: backendState === "NeedsLogin"
    readonly property bool daemonDown: backendState === "NoDaemon"
    property bool statusReady: false

    // True when the `tailscale` CLI itself isn't on PATH. Detected separately
    // because Quickshell's Process emits no onExited when the executable is
    // missing — the status/prefs/accounts calls silently no-op, so without
    // this probe the widget would sit on "Loading…" forever. Distinct from
    // daemonDown (binary present, tailscaled not running).
    property bool tailscaleMissing: false
    property bool _binaryProbed: false

    // True when the current user lacks operator rights on the Tailscale
    // daemon — status (read-only) still works, but up/down/set would be
    // rejected with "Access denied: prefs write access denied". Surfaced as a
    // warning so the user knows to run `sudo tailscale set --operator=$USER`.
    property bool operatorMissing: false

    // Login name of the user running the shell; compared against the
    // daemon's OperatorUser to detect missing operator rights.
    readonly property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    // Shown and copied literally — $USER expands in the user's own terminal.
    readonly property string operatorFixCommand: "sudo tailscale set --operator=$USER"

    // `tailscale login` is a *profile* operation and needs root — a non-root
    // login can't persist OperatorUser, so it silently strips this user's
    // operator rights (after which the daemon rejects every later up/down/set
    // and the UI locks to the OperatorWarning). So login is run through pkexec
    // (the DMS polkit agent prompts), and --operator=$USER is passed so the
    // root login re-establishes operator in the same step. Operator itself is
    // what lets up/down/set run *without* root, so those stay unprivileged.
    // Skipped for root (never needs an operator) and when the user is unknown.
    readonly property var operatorArgs: (currentUser && currentUser !== "root") ? ["--operator=" + currentUser] : []

    // Suppresses repeated operator-warning toasts while the condition persists.
    property bool _operatorWarned: false

    readonly property string stateLabel: {
        if (tailscaleMissing)
            return "Tailscale not installed";
        switch (backendState) {
        case "Running":
            return "Connected";
        case "Stopped":
            return "Disconnected";
        case "Starting":
            return "Starting…";
        case "NeedsLogin":
            return "Login required";
        case "NoDaemon":
            return "Daemon not running";
        case "":
            return "Loading…";
        default:
            return backendState;
        }
    }

    // --- network state ---
    property var selfDevice: null
    property var peers: []
    readonly property var allDevices: selfDevice ? [selfDevice].concat(peers) : peers
    property string currentTailnet: ""
    property string magicDnsSuffix: ""
    property var health: []

    readonly property var exitNodeCandidates: peers.filter(d => d.exitNodeOption)
    readonly property var activeExitNode: peers.find(d => d.exitNode) ?? null
    // True when no exit node is selected — neither live nor a persisted pref.
    readonly property bool noExitNodeSelected: !activeExitNode && prefExitNodeId === "" && prefExitNodeIp === ""
    readonly property var subnetRouters: allDevices.filter(d => d.routes.length > 0)
    readonly property int onlineCount: allDevices.filter(d => d.online).length
    readonly property int deviceCount: allDevices.length

    // --- accounts ---
    property var accounts: []                   // { id, tailnet, account, active }
    property string currentAccount: ""          // the active (*-marked) profile; "" when logged out

    // Remembered so the UI still knows which account is "current" when logged
    // out: Tailscale drops the active (*) marker from `switch --list` once a
    // profile needs login, which would otherwise leave the popout showing "No
    // account" even though a profile plainly exists. Seeded from persisted
    // plugin settings by the widget and refreshed whenever a profile is active.
    property string lastActiveAccount: ""

    // The account the UI treats as selected/current. Never blank while profiles
    // exist: the active profile, else the last one that was active (if still
    // present), else the sole/first profile. The connection card independently
    // shows the Log in button off backendState, so a logged-out selection still
    // reads correctly.
    readonly property string effectiveAccount: {
        const active = accounts.find(a => a.active);
        if (active)
            return active.account;
        if (accounts.length === 0)
            return "";
        const remembered = accounts.find(a => a.account === lastActiveAccount);
        return (remembered || accounts[0]).account;
    }

    // --- prefs ---
    property bool acceptRoutes: false
    property var advertisedRoutes: []           // CIDRs advertised by this device (exit-node routes excluded)
    property bool advertisesExitNode: false
    property bool exitNodeAllowLan: false
    property string prefExitNodeId: ""
    property string prefExitNodeIp: ""

    // --- dns ---
    // "Use Tailscale DNS" — whether this device accepts the DNS configuration
    // pushed by the coordination server (MagicDNS, split-DNS, search domains).
    // Maps to the CorpDNS pref / `tailscale set --accept-dns`.
    property bool acceptDns: false
    property bool dnsStatusReady: false
    // Whether MagicDNS is enabled tailnet-wide (an admin-console setting, not a
    // per-device pref) — the name→IP magic only works when this is on.
    property bool magicDnsEnabled: false
    // This device's fully-qualified MagicDNS name (trailing dot stripped).
    property string dnsSelfName: ""
    property var dnsSearchDomains: []           // extra domains appended to bare lookups
    property var dnsSplitRoutes: []             // { domain, resolvers } — per-domain resolvers

    // --- dns query tool ---
    property string dnsQueryResult: ""
    property bool dnsQuerying: false

    // --- transient ui state ---
    property bool busy: false
    property bool loginInProgress: false
    property string authUrl: ""
    property bool _loginCancelled: false

    // --- config (bound from plugin settings) ---
    property int pollIntervalMs: 5000
    property string copyField: "ip"

    // Watchdog: force-terminate a CLI call that runs longer than this, so a
    // hung `tailscale` never leaves the widget stuck (busy stuck true, or a
    // read proc stuck running which silently halts polling). Actions
    // (up/down/set) get a longer leash than the read-only polls; login is
    // excluded since it legitimately blocks on browser auth.
    property int cliTimeoutMs: 15000
    property int actionTimeoutMs: 60000

    // Login runs as root via pkexec, and a non-root parent can't signal a root
    // child — so neither the Cancel button nor a Process kill can stop it.
    // This bounds an abandoned login (browser auth never completed) so the
    // root process can't linger indefinitely; real sign-ins finish well within.
    property int loginTimeoutSecs: 180

    function refresh() {
        // Probe for the binary once at startup, then only while it's missing
        // (so a later install is picked up) — no point re-checking every poll
        // once we know it's present.
        if (!_binaryProbed || tailscaleMissing) {
            if (!whichProc.running)
                whichProc.running = true;
        }
        if (!statusProc.running)
            statusProc.running = true;
        if (!prefsProc.running)
            prefsProc.running = true;
        if (!accountsProc.running)
            accountsProc.running = true;
        if (!dnsStatusProc.running)
            dnsStatusProc.running = true;
    }

    function toggleConnection() {
        if (needsLogin) {
            startLogin();
            return;
        }
        if (isRunning)
            runAction(["tailscale", "down"], "Tailscale disconnected");
        else
            runAction(["tailscale", "up"], "Tailscale connected");
    }

    function switchAccount(account) {
        if (!account || account === currentAccount)
            return;
        runAction(["tailscale", "switch", account], "Switched to " + account);
    }

    function switchToNextAccount() {
        if (accounts.length < 2)
            return;
        const idx = accounts.findIndex(a => a.active);
        const next = accounts[(idx + 1) % accounts.length];
        switchAccount(next.account);
    }

    // True when the given peer is the selected exit node — matches the live
    // ExitNode flag or the persisted pref (by id or ip).
    function isExitNodeSelected(device) {
        return device.exitNode || prefExitNodeId === device.id || (prefExitNodeIp !== "" && prefExitNodeIp === device.ip);
    }

    function setExitNode(ip, name) {
        runAction(["tailscale", "set", "--exit-node=" + ip], ip ? "Exit node: " + name : "Exit node disabled");
    }

    function setExitNodeAllowLan(allow) {
        runAction(["tailscale", "set", "--exit-node-allow-lan-access=" + allow], "");
    }

    function setAcceptRoutes(accept) {
        runAction(["tailscale", "set", "--accept-routes=" + accept], "");
    }

    // Toggles "Use Tailscale DNS" (`--accept-dns`). When on, the daemon applies
    // the tailnet's DNS configuration (MagicDNS, split-DNS, search domains);
    // when off it reverts to the system default resolver.
    function setAcceptDns(accept) {
        runAction(["tailscale", "set", "--accept-dns=" + accept], accept ? "Using Tailscale DNS" : "Using system DNS");
    }

    // Read-only DNS lookup via the tailnet resolver (100.100.100.100). Runs on
    // its own process (not the mutating actionProc) since it produces output to
    // display and never changes state. `type` is an optional record type
    // (A, AAAA, CNAME, MX, TXT, …); empty means the CLI default (A).
    function runDnsQuery(name, type) {
        name = (name || "").trim();
        if (!name || dnsQuerying)
            return;
        if (tailscaleMissing) {
            dnsQueryResult = "tailscale CLI not found";
            return;
        }
        const cmd = ["tailscale", "dns", "query", name];
        const t = (type || "").trim().toUpperCase();
        if (t)
            cmd.push(t);
        dnsQueryResult = "";
        dnsQuerying = true;
        dnsQueryProc.command = cmd;
        dnsQueryProc.running = true;
    }

    // Clears the last DNS lookup result from the tab.
    function clearDnsQuery() {
        dnsQueryResult = "";
    }

    function setAdvertiseExitNode(advertise) {
        runAction(["tailscale", "set", "--advertise-exit-node=" + advertise], advertise ? "Advertising this device as an exit node" : "Stopped advertising exit node");
    }

    function setAdvertisedRoutes(text) {
        const routes = text.split(/[,\s]+/).filter(r => r.length > 0);
        // --advertise-routes replaces the full set, so re-assert the exit-node flag
        runAction(["tailscale", "set", "--advertise-routes=" + routes.join(","), "--advertise-exit-node=" + advertisesExitNode], routes.length ? "Advertising " + routes.join(", ") : "Cleared advertised routes");
    }

    function startLogin() {
        // Also guard on the process itself: a cancelled login keeps its root
        // pkexec child alive (we can't signal it) until `timeout` reaps it, so
        // block a restart until it has actually exited.
        if (loginInProgress || loginProc.running)
            return;
        authUrl = "";
        _loginCancelled = false;
        loginInProgress = true;
        loginProc.running = true;
    }

    function cancelLogin() {
        if (!loginProc.running)
            return;
        _loginCancelled = true;
        // The login runs as root under pkexec, so a signal from this non-root
        // process can't reach it. End it daemon-side instead: selecting an
        // existing profile stops the interactive-login watch, so the blocked
        // `tailscale login` returns and the pkexec process exits. During login
        // the operator pref is already set (login passes --operator), so this
        // unprivileged `switch` is permitted. If there's no profile to switch
        // to (very first login), the command's own `timeout` is the backstop.
        loginProc.signal(2);
        if (effectiveAccount)
            Quickshell.execDetached(["tailscale", "switch", effectiveAccount]);
    }

    function copyText(text) {
        if (!text)
            return;
        // Use DMS's own clipboard CLI rather than wl-copy: `dms` is always
        // present (it's running the shell), wl-clipboard is not a DMS
        // dependency, and this routes the copy into DMS's clipboard history.
        Quickshell.execDetached(["dms", "cl", "copy", text]);
        ToastService.showInfo("Copied " + text);
    }

    function copyDevice(device) {
        if (!device)
            return;
        copyText(copyField === "dns" ? device.dnsName : device.ip);
    }

    function runAction(cmd, successMessage) {
        // With no binary the exec would fail without an onExited, leaving
        // busy stuck true (and the watchdog disarms before it can fire), so
        // refuse up front rather than hang.
        if (tailscaleMissing) {
            ToastService.showError("Tailscale", "tailscale CLI not found");
            return;
        }
        if (busy) {
            ToastService.showWarning("Tailscale is busy, try again");
            return;
        }
        busy = true;
        actionProc.successMessage = successMessage;
        actionProc.command = cmd;
        actionProc.running = true;
    }

    function relTime(iso) {
        if (!iso || iso.startsWith("0001"))
            return "";
        const secs = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
        if (secs < 0)
            return "";
        if (secs < 60)
            return "just now";
        if (secs < 3600)
            return Math.floor(secs / 60) + "m ago";
        if (secs < 86400)
            return Math.floor(secs / 3600) + "h ago";
        return Math.floor(secs / 86400) + "d ago";
    }

    function untilTime(iso) {
        if (!iso || iso.startsWith("0001"))
            return "";
        const secs = Math.floor((new Date(iso).getTime() - Date.now()) / 1000);
        if (secs <= 0)
            return "expired";
        if (secs < 3600)
            return Math.floor(secs / 60) + " minutes";
        if (secs < 86400)
            return Math.floor(secs / 3600) + " hours";
        const days = Math.floor(secs / 86400);
        if (days < 60)
            return days + " days";
        if (days < 365)
            return Math.floor(days / 30) + " months";
        return Math.floor(days / 365) + " years";
    }

    // Logs the active account out of Tailscale. The daemon drops to
    // NeedsLogin and the account leaves the switch list, so the accounts UI
    // falls back to its logged-out state on the next refresh.
    function logout() {
        runAction(["tailscale", "logout"], "Logged out of Tailscale");
    }

    // Opens the Tailscale admin console for the active tailnet.
    function openAdminConsole() {
        Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin"]);
        ToastService.showInfo("Opening Tailscale admin console");
    }

    // Opens the Tailscale admin console filtered to this machine so its
    // key can be renewed (or expiry disabled) from the Machines page.
    function renewSession() {
        const q = selfDevice ? (selfDevice.name || selfDevice.hostName) : "";
        Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin/machines?q=" + encodeURIComponent(q)]);
        ToastService.showInfo("Opening Tailscale admin console");
    }

    function osIcon(os) {
        switch (os) {
        case "linux":
            return "computer";
        case "windows":
            return "desktop_windows";
        case "macOS":
            return "laptop_mac";
        case "iOS":
        case "iPadOS":
            return "phone_iphone";
        case "android":
            return "smartphone";
        case "tvOS":
            return "tv";
        default:
            return "device_unknown";
        }
    }

    function _mapDevice(node, users, isSelf) {
        const dns = (node.DNSName || "").replace(/\.$/, "");
        const ips = node.TailscaleIPs || [];
        return {
            id: node.ID || "",
            name: dns.split(".")[0] || node.HostName || "",
            hostName: node.HostName || "",
            dnsName: dns,
            ip: ips.find(a => a.indexOf(":") === -1) || ips[0] || "",
            ips: ips,
            os: node.OS || "",
            online: !!node.Online,
            active: !!node.Active,
            exitNode: !!node.ExitNode,
            exitNodeOption: !!node.ExitNodeOption,
            routes: node.PrimaryRoutes || [],
            lastSeen: node.LastSeen || "",
            keyExpiry: node.KeyExpiry || "",
            owner: (users && users[String(node.UserID)] && users[String(node.UserID)].LoginName) || "",
            isSelf: isSelf
        };
    }

    function _handleStatus(exitCode, out, err) {
        statusReady = true;
        if (exitCode !== 0) {
            selfDevice = null;
            peers = [];
            backendState = "NoDaemon";
            return;
        }
        let d;
        try {
            d = JSON.parse(out);
        } catch (e) {
            console.warn("tailscale: failed to parse status JSON:", e);
            return;
        }
        backendState = d.BackendState || "";
        magicDnsSuffix = d.MagicDNSSuffix || "";
        currentTailnet = (d.CurrentTailnet && d.CurrentTailnet.Name) || "";
        health = (d.Health || []).map(h => typeof h === "string" ? h : (h && h.Text) || "").filter(h => h.length > 0);
        selfDevice = d.Self ? _mapDevice(d.Self, d.User, true) : null;
        const list = [];
        const peerMap = d.Peer || {};
        for (const key in peerMap)
            list.push(_mapDevice(peerMap[key], d.User, false));
        list.sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name));
        peers = list;
    }

    function _handleAccounts(exitCode, out) {
        if (exitCode !== 0) {
            accounts = [];
            currentAccount = "";
            return;
        }
        const lines = out.trim().split("\n");
        const list = [];
        let current = "";
        for (let i = 1; i < lines.length; i++) {
            const parts = lines[i].trim().split(/\s+/);
            if (parts.length < 3)
                continue;
            let account = parts[2];
            const active = account.endsWith("*");
            if (active) {
                account = account.slice(0, -1);
                current = account;
            }
            list.push({
                id: parts[0],
                tailnet: parts[1],
                account: account,
                active: active
            });
        }
        accounts = list;
        currentAccount = current;
        // Keep the fallback fresh while an account is active, so it's accurate
        // the moment the profile later drops to needs-login.
        if (current)
            lastActiveAccount = current;
    }

    function _handlePrefs(exitCode, out) {
        if (exitCode !== 0)
            return;
        let p;
        try {
            p = JSON.parse(out);
        } catch (e) {
            return;
        }
        acceptRoutes = !!p.RouteAll;
        acceptDns = !!p.CorpDNS;
        exitNodeAllowLan = !!p.ExitNodeAllowLANAccess;
        prefExitNodeId = p.ExitNodeID || "";
        prefExitNodeIp = p.ExitNodeIP || "";
        const adv = p.AdvertiseRoutes || [];
        advertisesExitNode = adv.indexOf("0.0.0.0/0") !== -1 || adv.indexOf("::/0") !== -1;
        advertisedRoutes = adv.filter(r => r !== "0.0.0.0/0" && r !== "::/0");
        // Operator rights are per-user: OperatorUser must match *this* user
        // (granted via `sudo tailscale set --operator=$USER`), otherwise
        // mutating commands (up/down/set) are rejected even though status
        // still works. Root always has access. If we can't determine the
        // current user, fall back to just checking that an operator is set.
        //
        // Only meaningful while logged in, though: the daemon clears the
        // operator on logout (it doesn't persist with no active profile) and
        // login re-establishes it, so a missing operator while logged out is
        // expected — surfacing it would fire a bogus warning toast and lock the
        // UI (hiding the account) every time you sign out.
        if (currentUser === "root" || p.LoggedOut)
            setOperatorMissing(false);
        else
            setOperatorMissing(currentUser ? p.OperatorUser !== currentUser : !p.OperatorUser);
    }

    function _handleDnsStatus(exitCode, out) {
        dnsStatusReady = true;
        if (exitCode !== 0) {
            magicDnsEnabled = false;
            dnsSelfName = "";
            dnsSearchDomains = [];
            dnsSplitRoutes = [];
            return;
        }
        let d;
        try {
            d = JSON.parse(out);
        } catch (e) {
            return;
        }
        const tn = d.CurrentTailnet || {};
        magicDnsEnabled = !!tn.MagicDNSEnabled;
        dnsSelfName = (tn.SelfDNSName || "").replace(/\.$/, "");
        dnsSearchDomains = (d.SearchDomains || []).slice();
        const routes = d.SplitDNSRoutes || {};
        const list = [];
        for (const domain in routes) {
            const resolvers = routes[domain];
            // Each resolver is an object like { Addr: "1.2.3.4" } (Addr may be an
            // IP, IP:port, or a DoH URL) — not a bare string — so pull the Addr.
            const parts = (Array.isArray(resolvers) ? resolvers : [resolvers]).map(r => {
                if (r && typeof r === "object")
                    return r.Addr || JSON.stringify(r);
                return String(r);
            });
            list.push({
                domain: domain.replace(/\.$/, ""),
                resolvers: parts.join(", ")
            });
        }
        list.sort((a, b) => a.domain.localeCompare(b.domain));
        dnsSplitRoutes = list;
    }

    // One-click operator grant. Runs the same `tailscale set --operator=$USER`
    // as the copyable fallback command, but through pkexec so the session's
    // polkit agent (DMS registers one) shows a graphical password prompt
    // instead of the user needing a terminal. $USER can't expand here (no
    // shell, and pkexec runs as root anyway), so the resolved username is
    // passed literally. refresh() after unlocks the UI without waiting a poll.
    function grantOperator() {
        if (!currentUser || currentUser === "root")
            return;
        if (grantProc.running)
            return;
        grantProc.running = true;
    }

    function setOperatorMissing(missing) {
        if (operatorMissing === missing)
            return;
        operatorMissing = missing;
        if (missing && !_operatorWarned) {
            _operatorWarned = true;
            ToastService.showWarning("Tailscale CLI can't make changes for your user. Run: " + operatorFixCommand);
        } else if (!missing) {
            _operatorWarned = false;
        }
    }

    function _handleLoginLine(line) {
        const m = line.match(/https:\/\/\S+/);
        if (m && !authUrl) {
            authUrl = m[0];
            Quickshell.execDetached(["xdg-open", authUrl]);
            ToastService.showInfo("Complete the Tailscale sign-in in your browser");
        }
    }

    Timer {
        interval: root.pollIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Watchdogs — each is armed while its process runs and fires only if the
    // call overruns, killing it (which triggers the proc's onExited to reset
    // state). repeat:true (not single-shot) so binding `running` to the proc
    // isn't clobbered when the timer fires. Killing sets running=false again
    // via the binding, so it never double-fires.
    Timer {
        interval: root.cliTimeoutMs
        repeat: true
        running: statusProc.running
        onTriggered: statusProc.running = false
    }

    Timer {
        interval: root.cliTimeoutMs
        repeat: true
        running: prefsProc.running
        onTriggered: prefsProc.running = false
    }

    Timer {
        interval: root.cliTimeoutMs
        repeat: true
        running: accountsProc.running
        onTriggered: accountsProc.running = false
    }

    Timer {
        interval: root.cliTimeoutMs
        repeat: true
        running: dnsStatusProc.running
        onTriggered: dnsStatusProc.running = false
    }

    Timer {
        interval: root.cliTimeoutMs
        repeat: true
        running: dnsQueryProc.running
        onTriggered: dnsQueryProc.running = false
    }

    Timer {
        interval: root.actionTimeoutMs
        repeat: true
        running: actionProc.running
        onTriggered: {
            actionProc.timedOut = true;
            actionProc.running = false;
        }
    }

    // Existence probe: `command -v` exits 0 if `tailscale` is on PATH, 1 if
    // not. Runs via sh (always present), unlike the missing binary itself.
    Process {
        id: whichProc
        command: ["sh", "-c", "command -v tailscale"]
        onExited: exitCode => {
            root._binaryProbed = true;
            root.tailscaleMissing = exitCode !== 0;
            // Nothing else will ever set statusReady when the binary is gone
            // (the status Process emits no onExited), so unblock the UI here.
            if (root.tailscaleMissing)
                root.statusReady = true;
        }
    }

    Process {
        id: statusProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            id: statusOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: statusErr
            waitForEnd: true
        }
        onExited: exitCode => root._handleStatus(exitCode, statusOut.text, statusErr.text)
    }

    Process {
        id: prefsProc
        command: ["tailscale", "debug", "prefs"]
        stdout: StdioCollector {
            id: prefsOut
            waitForEnd: true
        }
        onExited: exitCode => root._handlePrefs(exitCode, prefsOut.text)
    }

    Process {
        id: accountsProc
        command: ["tailscale", "switch", "--list"]
        stdout: StdioCollector {
            id: accountsOut
            waitForEnd: true
        }
        onExited: exitCode => root._handleAccounts(exitCode, accountsOut.text)
    }

    Process {
        id: dnsStatusProc
        command: ["tailscale", "dns", "status", "--json"]
        stdout: StdioCollector {
            id: dnsStatusOut
            waitForEnd: true
        }
        onExited: exitCode => root._handleDnsStatus(exitCode, dnsStatusOut.text)
    }

    Process {
        id: dnsQueryProc
        stdout: StdioCollector {
            id: dnsQueryOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: dnsQueryErr
            waitForEnd: true
        }
        onExited: exitCode => {
            root.dnsQuerying = false;
            const out = (dnsQueryOut.text || "").trim();
            const err = (dnsQueryErr.text || "").trim();
            // The query CLI prints its human-readable result to stdout even on a
            // failed lookup (e.g. RCodeServerFailure), so prefer stdout and fall
            // back to stderr only when it's empty.
            root.dnsQueryResult = out || err || (exitCode === 0 ? "No output" : "Query failed (exit " + exitCode + ")");
        }
    }

    Process {
        id: actionProc

        property string successMessage: ""
        property bool timedOut: false

        stdout: StdioCollector {
            id: actionOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: actionErr
            waitForEnd: true
        }
        onExited: exitCode => {
            root.busy = false;
            if (actionProc.timedOut) {
                actionProc.timedOut = false;
                ToastService.showError("Tailscale", "Command timed out");
            } else if (exitCode === 0) {
                if (actionProc.successMessage)
                    ToastService.showInfo(actionProc.successMessage);
            } else {
                const msg = (actionErr.text || actionOut.text || "").trim();
                // Mutating commands fail with "Access denied: prefs write
                // access denied" when no operator is set — flag it so the
                // warning banner appears alongside the error toast.
                if (/access denied|operator/.test(msg.toLowerCase()))
                    root.setOperatorMissing(true);
                ToastService.showError("Tailscale", msg.split("\n")[0] || ("exit code " + exitCode));
            }
            root.refresh();
        }
    }

    Process {
        id: grantProc
        command: ["pkexec", "tailscale", "set", "--operator=" + root.currentUser]
        stderr: StdioCollector {
            id: grantErr
            waitForEnd: true
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                ToastService.showInfo("Operator access granted");
            } else {
                // pkexec exits non-zero and prints nothing when the user just
                // dismisses the prompt — only surface an error when there's
                // actual stderr (a real auth or command failure).
                const msg = (grantErr.text || "").trim().split("\n")[0];
                if (msg)
                    ToastService.showError("Tailscale", msg);
            }
            root.refresh();
        }
    }

    Process {
        id: loginProc
        // pkexec → root; `timeout` (also root) is the only thing that can stop
        // an abandoned login, since this non-root process can't signal its own
        // root child. --operator=$USER re-establishes operator during login.
        command: ["pkexec", "timeout", String(root.loginTimeoutSecs), "tailscale", "login"].concat(root.operatorArgs)
        stdout: SplitParser {
            onRead: data => root._handleLoginLine(data)
        }
        stderr: SplitParser {
            onRead: data => root._handleLoginLine(data)
        }
        onExited: exitCode => {
            root.loginInProgress = false;
            root.authUrl = "";
            if (exitCode === 0) {
                ToastService.showInfo("Logged in to Tailscale");
            } else if (exitCode === 126 || exitCode === 127) {
                // pkexec: user dismissed the password prompt or auth failed —
                // not an error worth a toast, they chose not to proceed.
            } else if (exitCode === 124 || root._loginCancelled) {
                // timeout killed an abandoned login, or the user hit Cancel.
            } else {
                ToastService.showError("Tailscale login failed");
            }
            root._loginCancelled = false;
            root.refresh();
        }
    }
}
