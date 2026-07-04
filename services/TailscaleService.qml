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

    // Suppresses repeated operator-warning toasts while the condition persists.
    property bool _operatorWarned: false

    readonly property string stateLabel: {
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
    property string currentAccount: ""

    // --- prefs ---
    property bool acceptRoutes: false
    property var advertisedRoutes: []           // CIDRs advertised by this device (exit-node routes excluded)
    property bool advertisesExitNode: false
    property bool exitNodeAllowLan: false
    property string prefExitNodeId: ""
    property string prefExitNodeIp: ""

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

    function refresh() {
        if (!statusProc.running)
            statusProc.running = true;
        if (!prefsProc.running)
            prefsProc.running = true;
        if (!accountsProc.running)
            accountsProc.running = true;
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

    function setAdvertiseExitNode(advertise) {
        runAction(["tailscale", "set", "--advertise-exit-node=" + advertise], advertise ? "Advertising this device as an exit node" : "Stopped advertising exit node");
    }

    function setAdvertisedRoutes(text) {
        const routes = text.split(/[,\s]+/).filter(r => r.length > 0);
        // --advertise-routes replaces the full set, so re-assert the exit-node flag
        runAction(["tailscale", "set", "--advertise-routes=" + routes.join(","), "--advertise-exit-node=" + advertisesExitNode], routes.length ? "Advertising " + routes.join(", ") : "Cleared advertised routes");
    }

    function startLogin() {
        if (loginInProgress)
            return;
        authUrl = "";
        _loginCancelled = false;
        loginInProgress = true;
        loginProc.running = true;
    }

    function cancelLogin() {
        if (loginProc.running) {
            _loginCancelled = true;
            loginProc.signal(2);
        }
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
        return Math.floor(secs / 86400) + " days";
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
        if (currentUser === "root")
            setOperatorMissing(false);
        else
            setOperatorMissing(currentUser ? p.OperatorUser !== currentUser : !p.OperatorUser);
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
        interval: root.actionTimeoutMs
        repeat: true
        running: actionProc.running
        onTriggered: {
            actionProc.timedOut = true;
            actionProc.running = false;
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
        id: loginProc
        command: ["tailscale", "login"]
        stdout: SplitParser {
            onRead: data => root._handleLoginLine(data)
        }
        stderr: SplitParser {
            onRead: data => root._handleLoginLine(data)
        }
        onExited: exitCode => {
            root.loginInProgress = false;
            root.authUrl = "";
            if (exitCode === 0)
                ToastService.showInfo("Logged in to Tailscale");
            else if (!root._loginCancelled)
                ToastService.showError("Tailscale login failed");
            root._loginCancelled = false;
            root.refresh();
        }
    }
}
