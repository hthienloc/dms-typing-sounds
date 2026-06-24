import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    pluginId: "typingSounds"
    pluginService: PluginService

    // Settings
    readonly property int volume: root.pluginData.volume ?? 50
    readonly property bool enabled: root.pluginData.enabled ?? true
    readonly property bool mouseEnabled: root.pluginData.mouseEnabled ?? false
    readonly property string selectedPackPath: root.pluginData.selectedPackPath ?? ""
    readonly property string selectedDevicePath: root.pluginData.selectedDevicePath ?? "all"

    // Runtime state
    property var currentDefines: ({})
    property var _pendingDefines: ({})
    property string currentPackId: ""
    property string cachePath: ""
    property var soundMap: ({})
    property bool isPreparing: false

    property bool inputToolMissing: false
    property bool mouseToolMissing: false
    property bool notInInputGroup: false
    readonly property string requiredTool: selectedDevicePath === "all" ? "libinput" : "evtest"

    IpcHandler {
        target: "typingSounds"

        function toggle(): string {
            const newState = !root.enabled;
            root.saveSetting("enabled", newState);
            return newState ? "Typing sounds enabled" : "Typing sounds disabled";
        }

        function enable(): string {
            root.saveSetting("enabled", true);
            return "Typing sounds enabled";
        }

        function disable(): string {
            root.saveSetting("enabled", false);
            return "Typing sounds disabled";
        }
    }

    Component.onCompleted: {
        // Self-register in PluginService
        if (!pluginService.pluginInstances[pluginId]) {
            const newInstances = Object.assign({}, pluginService.pluginInstances);
            newInstances[pluginId] = root;
            pluginService.pluginInstances = newInstances;
        }
        
        checkTools();
        verifyAndLoadPack();
    }

    function cleanup() {
        inputProc.running = false;
        mouseProc.running = false;
        sliceProc.running = false;
        currentDefines = {};
        soundMap = {};
    }

    Component.onDestruction: {
        cleanup();
        if (pluginService.pluginInstances[pluginId] === root) {
            const newInstances = Object.assign({}, pluginService.pluginInstances);
            delete newInstances[pluginId];
            pluginService.pluginInstances = newInstances;
        }
    }

    onSelectedPackPathChanged: {
        verifyAndLoadPack();
    }

    onSelectedDevicePathChanged: {
        inputProc.running = false;
        inputRestartTimer.restart();
    }

    Timer {
        id: inputRestartTimer
        interval: 200
        onTriggered: inputProc.running = true
    }

    function checkTools() {
        toolCheck.running = false;
        toolCheck.running = true;
        groupCheck.running = false;
        groupCheck.running = true;
        mouseToolCheck.running = false;
        mouseToolCheck.running = true;
    }

    Process {
        id: toolCheck
        command: ["sh", "-c", "command -v " + root.requiredTool + " >/dev/null 2>&1"]
        running: false
        onExited: (exitCode) => {
            root.inputToolMissing = (exitCode !== 0);
        }
    }

    Process {
        id: mouseToolCheck
        command: ["sh", "-c", "command -v libinput >/dev/null 2>&1"]
        running: false
        onExited: (exitCode) => {
            root.mouseToolMissing = (exitCode !== 0);
        }
    }

    Process {
        id: groupCheck
        command: ["sh", "-c", "id -nG | tr ' ' '\n' | grep -qx input"]
        running: false
        onExited: (exitCode) => {
            root.notInInputGroup = (exitCode !== 0);
        }
    }

    FileView {
        id: configFileReader
        printErrors: false
        onLoaded: {
            try {
                const config = JSON.parse(text());
                if (!config) return;
                
                const packId = config.id || "default_pack";
                const homeCache = Paths.expandTilde("~/.cache/dms-typing-sounds") + "/" + packId;
                
                root.currentPackId = packId;
                root.cachePath = homeCache;
                root._pendingDefines = config.defines || {};
                cacheMarkerReader.path = homeCache + "/.complete";
            } catch(e) {
                console.warn("[TypingSounds] Failed to parse config.json:", e);
            }
        }
        onLoadFailed: {
            console.warn("[TypingSounds] Failed to read config.json:", path);
        }
    }

    FileView {
        id: cacheMarkerReader
        printErrors: false
        onLoaded: {
            console.log("[TypingSounds] Sound pack cache is complete for:", root.currentPackId);
            root.currentDefines = root._pendingDefines;
        }
        onLoadFailed: {
            console.log("[TypingSounds] Sound pack cache is incomplete. Slicing:", root.currentPackId);
            root.isPreparing = true;
            sliceProc.command = [
                "python3",
                Paths.expandTilde("~/.config/DankMaterialShell/plugins/typingSounds/slice_audio.py"),
                "--pack-dir", root.selectedPackPath,
                "--cache-dir", root.cachePath
            ];
            sliceProc.running = true;
        }
    }

    function verifyAndLoadPack() {
        if (!selectedPackPath) {
            currentDefines = {};
            currentPackId = "";
            cachePath = "";
            return;
        }

        if (sliceProc.running) {
            sliceProc.running = false;
        }
        root.isPreparing = false;

        configFileReader.path = selectedPackPath + "/config.json";
    }

    Process {
        id: sliceProc
        running: false
        onExited: (exitCode) => {
            root.isPreparing = false;
            if (exitCode === 0) {
                console.log("[TypingSounds] Sound pack sliced successfully.");
                root.currentDefines = root._pendingDefines;
            } else {
                console.error("[TypingSounds] Slicing failed with exit code:", exitCode);
            }
        }
    }

    function preSlicePack(packPath) {
        if (!packPath) return;
        if (preSliceQueue.indexOf(packPath) !== -1) return;
        preSliceQueue = preSliceQueue.concat([packPath]);
        const script = `
import os, json, sys, subprocess
pack_dir = sys.argv[1]
cache_base = sys.argv[2]
slice_script = sys.argv[3]
try:
    with open(os.path.join(pack_dir, 'config.json')) as f:
        cfg = json.load(f)
        pack_id = cfg.get('id', 'pack')
except:
    sys.exit(0)
cache_dir = os.path.join(cache_base, pack_id)
marker = os.path.join(cache_dir, '.complete')
if not os.path.exists(marker):
    os.makedirs(cache_dir, exist_ok=True)
    subprocess.run(['python3', slice_script, '--pack-dir', pack_dir, '--cache-dir', cache_dir])
`;
        Proc.runCommand("typingSounds.preSlice", [
            "python3", "-c", script,
            packPath,
            Paths.expandTilde("~/.cache/dms-typing-sounds"),
            Paths.expandTilde("~/.config/DankMaterialShell/plugins/typingSounds/slice_audio.py")
        ]);
    }

    property var preSliceQueue: []

    // Dynamically load sound effects
    Instantiator {
        model: Object.keys(root.currentDefines)
        delegate: SoundEffectWrapper {
            keycode: modelData
            sourcePath: "file://" + root.cachePath + "/" + modelData + ".wav"
            volumeValue: root.volume / 100.0

            Component.onCompleted: {
                root.soundMap[keycode] = this;
            }
            Component.onDestruction: {
                delete root.soundMap[keycode];
            }
        }
    }

    function triggerKeySound(keycode) {
        if (!root.enabled || root.isPreparing) return;
        const effect = root.soundMap[keycode.toString()];
        if (effect) {
            effect.play();
        } else {
            // Fallback to general space/enter if specific key is missing
            // standard fallback keycode is space (57) or enter (28)
            const fallback = root.soundMap["57"];
            if (fallback) fallback.play();
        }
    }

    function triggerMouseSound() {
        root.triggerKeySound("30");
    }

    // Input monitoring process
    Process {
        id: inputProc
        command: {
            const cmd = selectedDevicePath === "all"
                ? ["libinput", "debug-events", "--show-keycodes"]
                : ["evtest", selectedDevicePath];
            console.log("[TypingSounds] Starting input process:", JSON.stringify(cmd));
            return cmd;
        }
        running: root.enabled && !root.inputToolMissing

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("EV_KEY")) {
                    const keyMatch = data.match(/code\s+(\d+)/);
                    if (keyMatch && data.includes("value 1")) {
                        const code = parseInt(keyMatch[1]);
                        if (code >= 272 && code <= 287) {
                            if (root.mouseEnabled) {
                                root.triggerMouseSound();
                            }
                        } else {
                            root.triggerKeySound(code);
                        }
                    }
                } else if (data.includes("KEYBOARD_KEY")) {
                    const keyMatch = data.match(/\((\d+)\)/);
                    if (keyMatch && data.includes("pressed")) {
                        root.triggerKeySound(keyMatch[1]);
                    }
                } else if (root.mouseEnabled && data.includes("POINTER_BUTTON")) {
                    if (data.includes("pressed")) {
                        root.triggerMouseSound();
                    }
                }
            }
        }

        stderr: StdioCollector {}
    }

    // Mouse monitoring process for specific device selection
    Process {
        id: mouseProc
        command: ["libinput", "debug-events"]
        running: root.enabled && root.mouseEnabled && root.selectedDevicePath !== "all" && !root.mouseToolMissing

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("POINTER_BUTTON") && data.includes("pressed")) {
                    root.triggerMouseSound();
                }
            }
        }

        stderr: StdioCollector {}
    }

    function saveSetting(key, value) {
        try {
            pluginService.savePluginData(pluginId, key, value);
            if (pluginData) pluginData[key] = value;
        } catch(e) {
            console.warn("[TypingSounds] Failed to save setting:", key, e);
        }
    }
}
