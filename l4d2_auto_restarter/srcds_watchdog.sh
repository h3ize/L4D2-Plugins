#!/usr/bin/env php
<?php
declare(strict_types=1);

ob_implicit_flush(true);
error_reporting(E_ALL);

$sourceQueryPath = __DIR__ . '/SourceQuery';

if (!class_exists(\xPaw\SourceQuery\SourceQuery::class) && !file_exists($sourceQueryPath . '/SourceQuery.php')) {
    echo "[" . date('Y-m-d H:i:s') . "] SourceQuery not found globally → installing locally...\n";
    if (!file_exists($sourceQueryPath)) mkdir($sourceQueryPath, 0755, true);
    $downloadZip = __DIR__ . '/sourcequery.zip';
    $tmpDir = __DIR__ . '/sourcequery_tmp';
    shell_exec("curl -L https://github.com/xPaw/PHP-Source-Query-Class/archive/refs/heads/master.zip -o $downloadZip");
    if (file_exists($tmpDir)) shell_exec("rm -rf $tmpDir");
    mkdir($tmpDir, 0755);
    shell_exec("unzip -q $downloadZip -d $tmpDir");
    $extractedDirs = glob("$tmpDir/*", GLOB_ONLYDIR);
    if (!empty($extractedDirs)) {
        $extractedRoot = $extractedDirs[0];
        $librarySource = "$extractedRoot/SourceQuery";
        if (!file_exists($librarySource)) {
            echo "[" . date('Y-m-d H:i:s') . "] Error: SourceQuery subdirectory not found.\n";
        } else {
            if (file_exists($sourceQueryPath)) shell_exec("rm -rf $sourceQueryPath");
            mkdir($sourceQueryPath, 0755, true);
            shell_exec("cp -r $librarySource/* $sourceQueryPath/");
            echo "[" . date('Y-m-d H:i:s') . "] SourceQuery installed locally.\n";
        }
    } else {
        echo "[" . date('Y-m-d H:i:s') . "] Error: No extracted directory found.\n";
    }
    unlink($downloadZip);
    shell_exec("rm -rf $tmpDir");
}

require_once $sourceQueryPath . '/BaseSocket.php';
require_once $sourceQueryPath . '/BaseRcon.php';
require_once $sourceQueryPath . '/Buffer.php';
require_once $sourceQueryPath . '/Socket.php';
require_once $sourceQueryPath . '/SourceQuery.php';
require_once $sourceQueryPath . '/SourceRcon.php';
require_once $sourceQueryPath . '/GoldSourceRcon.php';
require_once $sourceQueryPath . '/Exception/SourceQueryException.php';
require_once $sourceQueryPath . '/Exception/InvalidPacketException.php';
require_once $sourceQueryPath . '/Exception/AuthenticationException.php';
require_once $sourceQueryPath . '/Exception/InvalidArgumentException.php';
require_once $sourceQueryPath . '/Exception/SocketException.php';

use xPaw\SourceQuery\SourceQuery;
use xPaw\SourceQuery\SourceRcon;
use xPaw\SourceQuery\Socket;

$SRCDS_DIR = '/etc/init.d';
$CHECK_INTERVAL = 15;
$COOLDOWN = 60;
$EMPTY_THRESHOLD = 300;
$PORT_CHECK_TIMEOUT = 10;

$DEBUG_MODE = 0;

$FEATURES = [
    'restart_on_map_mismatch_when_empty' => true,
    'restart_on_hostname_mismatch'       => true,
    'restart_if_not_listening_on_port'   => true,
    'restart_if_screen_not_running'      => true,
];

$LAST_RESTART = [];
$LAST_EMPTY   = [];
$LAST_FAIL    = [];

function logMsg(string $msg): void {
    echo "[" . date('Y-m-d H:i:s') . "] $msg\n";
}

function getServerCfg(string $srcdsScript): array {
    preg_match('/srcds(\d+)/', $srcdsScript, $m);
    $num = $m[1] ?? '1';
    $cfgPath = "/home/steam/Steam/steamapps/common/l4d2/left4dead2/cfg/server{$num}.cfg";
    if (!file_exists($cfgPath)) return [];

    $cfg = file_get_contents($cfgPath);

    // Extract RCON password
    preg_match('/rcon_password\s+"?([^"\s]+)"?/', $cfg, $rcon);
    $rconPassword = $rcon[1] ?? null;

    // Extract hostname
    preg_match('/hostname\s+"?([^"\r\n]+)"?/', $cfg, $h);
    $hostname = $h[1] ?? null;

    return [
        'rcon'     => $rconPassword,
        'hostname' => $hostname,
    ];
}

function isScreenRunning(string $service): bool {
    $output = shell_exec("pgrep -f \"$service\"");
    return !empty($output);
}

function startServer(string $service, string $SRCDS_DIR): void {
    logMsg("Starting missing session → $service");
    $output = shell_exec("sudo $SRCDS_DIR/$service start 2>&1");
    logMsg("Start output: " . ($output ?: "no output"));
}

function portIsReachable(string $ip, int $port, int $timeout): bool {
    $fp = @fsockopen($ip, $port, $errno, $errstr, $timeout);
    if ($fp !== false) {
        fclose($fp);
        return true;
    }
    return false;
}

function restartServer(string $service, array &$LAST_RESTART, int $COOLDOWN, string $SRCDS_DIR): void {
    $now = time();
    if (isset($LAST_RESTART[$service]) && $now - $LAST_RESTART[$service] < $COOLDOWN) {
        logMsg("$service restart skipped (cooldown active)");
        return;
    }
    logMsg("Executing restart → $service");
    $LAST_RESTART[$service] = $now;
    $output = shell_exec("$SRCDS_DIR/$service restart 2>&1");
    logMsg("Restart output: " . ($output ?: "no output / failed"));
}

function queryServer(string $ip, int $port, string $rconPassword): array {
    $players = 0;
    $hostname = '';
    $current_map = '';

    $Query = new SourceQuery();
    try {
        $Query->Connect($ip, $port, 2, SourceQuery::SOURCE);
        $info = $Query->GetInfo();
        $playersInfo = $Query->GetPlayers();
        foreach ($playersInfo as $p) {
            if (!empty($p['Name'])) $players++;
        }
        $hostname = $info['HostName'] ?? '';
        $current_map = $info['Map'] ?? '';
    } catch (\Throwable $e) {
        try {
            $Socket = new Socket();
            $Socket->Open($ip, $port, 2, SourceQuery::SOURCE);
            $Rcon = new SourceRcon($Socket);
            $Rcon->Open();
            $Rcon->Authorize($rconPassword);
            $status = $Rcon->Command('status');
            $Rcon->Close();
            $Socket->Close();

            foreach (explode("\n", $status) as $line) {
                $line = trim($line);
                if (preg_match('/^hostname\s*:\s*(.+)$/i', $line, $m)) $hostname = $m[1];
                if (preg_match('/^map\s*:\s*(\S+)/i', $line, $m)) $current_map = $m[1];
                if (preg_match('/^players\s*:\s*(\d+)/i', $line, $m)) $players = (int)$m[1];
            }
        } catch (\Throwable $ex) {
            logMsg("Query & RCON failed → $ip:$port " . $ex->getMessage());
        }
    } finally {
        try { $Query->Disconnect(); } catch (\Throwable) {}
    }

    return compact('players', 'hostname', 'current_map');
}

while (true) {
    $services = $DEBUG_MODE ? ["$SRCDS_DIR/srcds1"] : glob("$SRCDS_DIR/srcds*");

    foreach ($services as $srcdsScript) {
        if (!is_file($srcdsScript) || !is_executable($srcdsScript)) continue;

        $service = basename($srcdsScript);
        $cfg = getServerCfg($srcdsScript);
        $RCON_PASS = $cfg['rcon'] ?? null;
        $EXPECTED_HOSTNAME = $cfg['hostname'] ?? '';

        $content = file_get_contents($srcdsScript);
        preg_match('/IP=(.*)/',      $content, $ipM);
        preg_match('/PORT=(.*)/',    $content, $portM);
        preg_match('/\+map\s+([^\s]+)/', $content, $mapM);

        $EXPECTED_MAP = $mapM[1] ?? null;
        $IP   = trim($ipM[1] ?? '');
        $PORT = (int)trim($portM[1] ?? 0);

        logMsg("$service → IP=$IP PORT=$PORT MAP=$EXPECTED_MAP HOSTNAME=" . ($EXPECTED_HOSTNAME ?: 'not set') . " RCON=" . ($RCON_PASS ? "set" : "missing"));

        if (!$IP || !$PORT || !$RCON_PASS || !$EXPECTED_MAP) {
            logMsg("$service → missing critical config → skipping");
            continue;
        }

        $now = time();

        // Check screen session
        if ($FEATURES['restart_if_screen_not_running'] && !isScreenRunning($service)) {
            logMsg("$service → screen session not found");
            startServer($service, $SRCDS_DIR);
            sleep(10);
            continue;
        }

        // Query server
        $info = queryServer($IP, $PORT, $RCON_PASS);
        $players     = $info['players'];
        $current_map = $info['current_map'];
        $hostname    = $info['hostname'];

        if ($players > 0) {
            logMsg("$service → has players → skipping further checks");
            unset($LAST_EMPTY[$service], $LAST_FAIL[$service]);
            continue;
        }

        // ── Empty server checks ──────────────────────────────────────

        $failureReasons = [];

        // Port check
        $portOk = true;
        if ($FEATURES['restart_if_not_listening_on_port']) {
            $portOk = portIsReachable($IP, $PORT, $PORT_CHECK_TIMEOUT);
            if (!$portOk) {
                $failureReasons[] = "port $PORT not reachable";
            }
        }

        // Map mismatch
        if ($FEATURES['restart_on_map_mismatch_when_empty'] && $current_map !== $EXPECTED_MAP) {
            $failureReasons[] = "map mismatch ($current_map ≠ $EXPECTED_MAP)";
        }

        // Hostname mismatch (now using value from server.cfg)
        if ($FEATURES['restart_on_hostname_mismatch'] && $EXPECTED_HOSTNAME !== '' && $hostname !== $EXPECTED_HOSTNAME) {
            $failureReasons[] = "hostname mismatch ($hostname ≠ $EXPECTED_HOSTNAME)";
        }

        // ── Decision ─────────────────────────────────────────────────

        if (empty($failureReasons)) {
            logMsg("$service → empty but no failure conditions met → keeping alive");
            unset($LAST_EMPTY[$service], $LAST_FAIL[$service]);
            continue;
        }

        // There is at least one failure → track time
        $LAST_EMPTY[$service] = $LAST_EMPTY[$service] ?? $now;
        $LAST_FAIL[$service]  = $LAST_FAIL[$service]  ?? $now;

        $failDuration = $now - $LAST_FAIL[$service];

        if ($failDuration >= $EMPTY_THRESHOLD) {
            $reasonList = implode(", ", $failureReasons);
            logMsg("$service empty + failing for {$failDuration}s → restarting ($reasonList)");
            restartServer($service, $LAST_RESTART, $COOLDOWN, $SRCDS_DIR);
            unset($LAST_EMPTY[$service], $LAST_FAIL[$service]);
        } else {
            logMsg("$service empty + failing for {$failDuration}s / needed $EMPTY_THRESHOLD → waiting");
        }
    }

    sleep($CHECK_INTERVAL);
}