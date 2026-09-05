<?php
/**
 * WizWiz IP Poller
 * ----------------
 * This file replaces the Telegram Webhook when the bot runs on a plain IP
 * (no domain, no SSL). It uses Long Polling (getUpdates) to receive updates
 * and forwards each one to bot.php via a local HTTP request.
 *
 * Run it as a systemd service (see install-ip.sh) or manually:
 *   php poller.php
 */

error_reporting(0);

require_once __DIR__ . '/baseInfo.php';

$localUrl = 'http://127.0.0.1/wizwizxui-timebot/bot.php';
$apiBase  = "https://api.telegram.org/bot" . $botToken;

// Make sure no webhook is set (webhook and getUpdates cannot be used together)
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $apiBase . "/deleteWebhook");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_exec($ch);
curl_close($ch);

$offset = 0;

echo "[poller] Started. Listening for updates...\n";

while (true) {
    try {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $apiBase . "/getUpdates");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
            'offset'  => $offset,
            'timeout' => 50,          // long polling: wait up to 50s for updates
            'allowed_updates' => json_encode(['message', 'callback_query']),
        ]));
        $res = curl_exec($ch);
        curl_close($ch);

        $data = json_decode($res);

        if ($data === null) {
            // Network hiccup — wait and retry
            sleep(2);
            continue;
        }

        if ($data->ok === false) {
            // 409 Conflict: another getUpdates is running (e.g. webhook still active)
            if (strpos($data->description ?? '', 'Conflict') !== false) {
                echo "[poller] Conflict detected. Make sure no webhook is set. Retrying in 5s...\n";
                sleep(5);
                continue;
            }
            // 429 Too Many Requests
            if (isset($data->parameters->retry_after)) {
                sleep($data->parameters->retry_after + 1);
                continue;
            }
            echo "[poller] API error: " . ($data->description ?? 'unknown') . "\n";
            sleep(3);
            continue;
        }

        $updates = $data->result ?? [];

        foreach ($updates as $update) {
            $offset = $update->update_id + 1;

            // Forward the raw update JSON to bot.php
            $ch2 = curl_init();
            curl_setopt($ch2, CURLOPT_URL, $localUrl);
            curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch2, CURLOPT_POST, true);
            curl_setopt($ch2, CURLOPT_POSTFIELDS, json_encode($update));
            curl_setopt($ch2, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
            $localRes = curl_exec($ch2);
            $httpCode = curl_getinfo($ch2, CURLINFO_HTTP_CODE);
            curl_close($ch2);

            if ($httpCode !== 200) {
                echo "[poller] bot.php returned HTTP $httpCode for update " . $update->update_id . "\n";
            }
        }
    } catch (Throwable $e) {
        echo "[poller] Exception: " . $e->getMessage() . "\n";
        sleep(3);
    }
}
