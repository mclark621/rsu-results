<?php
session_start();
require('ApiConfig.php');
require('RunSignupRestClient.class.php');

// Require race_id for settings
$raceId = isset($_GET['race_id']) ? $_GET['race_id'] : (isset($_POST['race_id']) ? $_POST['race_id'] : '');

// Sponsor logo upload endpoint
if (isset($_POST['upload_sponsor']) && $_POST['upload_sponsor'] === '1') {
    header('Content-Type: application/json');
    $raceId = isset($_POST['race_id']) ? $_POST['race_id'] : '';
    if (!$raceId || !isset($_FILES['sponsor_logo']) || $_FILES['sponsor_logo']['error'] !== UPLOAD_ERR_OK) {
        echo json_encode(['ok' => false, 'error' => 'invalid']);
        exit;
    }
    $allowed = ['image/png' => 'png', 'image/jpeg' => 'jpg', 'image/webp' => 'webp', 'image/gif' => 'gif'];
    $mime = mime_content_type($_FILES['sponsor_logo']['tmp_name']);
    if (!isset($allowed[$mime])) {
        echo json_encode(['ok' => false, 'error' => 'type']);
        exit;
    }
    $raw = @file_get_contents($_FILES['sponsor_logo']['tmp_name']);
    if ($raw === false) { echo json_encode(['ok'=>false,'error'=>'read']); exit; }
    $dataUrl = 'data:' . $mime . ';base64,' . base64_encode($raw);
    try {
        $db = new SQLite3(__DIR__ . '/selfie.sqlite');
        $db->busyTimeout(5000);
        @$db->exec('PRAGMA journal_mode=WAL');
        $db->exec('CREATE TABLE IF NOT EXISTS color_settings (
            race_id TEXT PRIMARY KEY,
            race_name TEXT,
            label_color TEXT,
            data_color TEXT,
            name_color TEXT,
            sponsor_logo TEXT,
            background_color TEXT,
            updated_at TEXT
        )');
        // ensure column
        $colExists = false; $ti = $db->query("PRAGMA table_info(color_settings)");
        if ($ti) { while ($row = $ti->fetchArray(SQLITE3_ASSOC)) { if (($row['name']??'')==='sponsor_logo'){ $colExists=true; break; } } }
        if (!$colExists) { $db->exec('ALTER TABLE color_settings ADD COLUMN sponsor_logo TEXT'); }
        $ins = $db->prepare('INSERT INTO color_settings (race_id, sponsor_logo, updated_at) VALUES (:race_id, :sponsor_logo, :updated_at)
            ON CONFLICT(race_id) DO UPDATE SET sponsor_logo=excluded.sponsor_logo, updated_at=excluded.updated_at');
        $ins->bindValue(':race_id', $raceId, SQLITE3_TEXT);
        $ins->bindValue(':sponsor_logo', $dataUrl, SQLITE3_TEXT);
        $ins->bindValue(':updated_at', date('c'), SQLITE3_TEXT);
        $ins->execute();
        $ins->close();
        $db->close();
    } catch (Exception $e) { echo json_encode(['ok'=>false,'error'=>'db']); exit; }
    echo json_encode(['ok'=>true]);
    exit;
}

// Read colors
if (isset($_GET['get_colors']) && $_GET['get_colors'] === '1') {
    header('Content-Type: application/json');
    if (!$raceId) { echo json_encode(['ok'=>false,'error'=>'race_id required']); exit; }
    try {
        $db = new SQLite3(__DIR__ . '/selfie.sqlite');
        $db->busyTimeout(5000); @$db->exec('PRAGMA journal_mode=WAL');
        $db->exec('CREATE TABLE IF NOT EXISTS color_settings (
            race_id TEXT PRIMARY KEY,
            race_name TEXT,
            label_color TEXT,
            data_color TEXT,
            name_color TEXT,
            sponsor_logo TEXT,
            updated_at TEXT
        )');
        // ensure background_color column exists
        $colExistsBg = false; $ti2 = $db->query("PRAGMA table_info(color_settings)");
        if ($ti2) { while ($row2 = $ti2->fetchArray(SQLITE3_ASSOC)) { if (($row2['name']??'')==='background_color'){ $colExistsBg=true; break; } } }
        if (!$colExistsBg) { $db->exec('ALTER TABLE color_settings ADD COLUMN background_color TEXT'); }
        $stmt = $db->prepare('SELECT race_name, label_color, data_color, name_color, sponsor_logo, background_color, updated_at FROM color_settings WHERE race_id = :race_id');
        $stmt->bindValue(':race_id', $raceId, SQLITE3_TEXT);
        $res = $stmt->execute(); $row = $res ? $res->fetchArray(SQLITE3_ASSOC) : null;
        if ($res) { $res->finalize(); } $stmt=null; $db->close();
        echo json_encode(['ok'=>true,'race_id'=>$raceId] + ($row?:[]));
    } catch (Exception $e) { echo json_encode(['ok'=>false]); }
    exit;
}

// Save colors
if (isset($_POST['save_colors']) && $_POST['save_colors'] === '1') {
    header('Content-Type: application/json');
    $raceName = isset($_POST['race_name']) ? $_POST['race_name'] : '';
    $labelColor = isset($_POST['label_color']) ? $_POST['label_color'] : '#90D5FF';
    $dataColor = isset($_POST['data_color']) ? $_POST['data_color'] : '#d1842a';
    $nameColor = isset($_POST['name_color']) ? $_POST['name_color'] : '#000000';
    $bgColor = isset($_POST['background_color']) ? $_POST['background_color'] : '#f4f7f6';
    if ($raceId) {
        try {
            $db = new SQLite3(__DIR__ . '/selfie.sqlite');
            $db->busyTimeout(5000); @$db->exec('PRAGMA journal_mode=WAL');
            $db->exec('CREATE TABLE IF NOT EXISTS color_settings (
                race_id TEXT PRIMARY KEY,
                race_name TEXT,
                label_color TEXT,
                data_color TEXT,
                name_color TEXT,
                sponsor_logo TEXT,
                background_color TEXT,
                updated_at TEXT
            )');
            // ensure background column exists
            $colExistsBg = false; $ti2 = $db->query("PRAGMA table_info(color_settings)");
            if ($ti2) { while ($row2 = $ti2->fetchArray(SQLITE3_ASSOC)) { if (($row2['name']??'')==='background_color'){ $colExistsBg=true; break; } } }
            if (!$colExistsBg) { $db->exec('ALTER TABLE color_settings ADD COLUMN background_color TEXT'); }
            $ins = $db->prepare('INSERT INTO color_settings (race_id, race_name, label_color, data_color, name_color, background_color, updated_at) VALUES (:race_id, :race_name, :label_color, :data_color, :name_color, :background_color, :updated_at)
                ON CONFLICT(race_id) DO UPDATE SET race_name=excluded.race_name, label_color=excluded.label_color, data_color=excluded.data_color, name_color=excluded.name_color, background_color=excluded.background_color, updated_at=excluded.updated_at');
            $ins->bindValue(':race_id', $raceId, SQLITE3_TEXT);
            $ins->bindValue(':race_name', $raceName, SQLITE3_TEXT);
            $ins->bindValue(':label_color', $labelColor, SQLITE3_TEXT);
            $ins->bindValue(':data_color', $dataColor, SQLITE3_TEXT);
            $ins->bindValue(':name_color', $nameColor, SQLITE3_TEXT);
            $ins->bindValue(':background_color', $bgColor, SQLITE3_TEXT);
            $ins->bindValue(':updated_at', date('c'), SQLITE3_TEXT);
            $ins->execute(); $ins=null; $db->close();
            echo json_encode(['ok'=>true]);
        } catch (Exception $e) { echo json_encode(['ok'=>false]); }
    } else {
        echo json_encode(['ok'=>false]);
    }
    exit;
}

// Render settings UI
?><!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Settings - Bay City Timing & Events</title>
    <link rel="stylesheet" href="assets/style/stylesheets.css">
    <style>
        .btn-primary-like { background:#ff8c00; color:#fff; border:none; border-radius:8px; padding:10px 14px; font-weight:600; cursor:pointer; letter-spacing:0.5px; }
        .btn-primary-like:hover { background:#e67e00; }
        .btn-secondary-like { background:#f0f0f0; color:#333; border:none; border-radius:8px; padding:10px 14px; font-weight:600; cursor:pointer; }
        .btn-secondary-like:hover { background:#e6e6e6; }
        .btn-link-like { text-decoration:none; display:inline-block; }
    </style>
</head>
<body>
<div class="form-container">
    <div class="logo">
        <img src="assets/img/bctlogo.png" alt="Bay City Timing & Events Logo">
    </div>
    <?php if (!$raceId) { ?>
        <div class="search-type-container">Please open Settings from the race picker after selecting a race.</div>
        <div style="margin-top:10px;"><a href="selfie.php">Back to race picker</a></div>
    <?php } else { ?>
    <form class="stylish-form" id="settingsForm" method="POST" action="#">
        <input type="hidden" id="race_id" name="race_id" value="<?php echo htmlspecialchars($raceId); ?>">
        <label for="label_color">Results Label Color</label>
        <input type="color" id="label_color" name="label_color" value="#90D5FF">
        
        <label for="data_color">Results Data Color</label>
        <input type="color" id="data_color" name="data_color" value="#d1842a">

        <label for="name_color">Participant Name Color</label>
        <input type="color" id="name_color" name="name_color" value="#000000">

        <label for="background_color">Page Background Color</label>
        <input type="color" id="background_color" name="background_color" value="#f4f7f6">

        <label for="sponsor_logo">Sponsor Logo</label>
        <input type="file" id="sponsor_logo" name="sponsor_logo" accept="image/png,image/jpeg,image/webp,image/gif">
        <div style="display:flex; gap:10px; align-items:center; margin-top:8px;">
            <button type="button" id="uploadSponsorBtn" class="btn-secondary-like">Upload Sponsor Logo</button>
            <span id="uploadSponsorStatus" style="font-size:0.9em; color:#555;"></span>
        </div>
        <div id="sponsorThumb" style="margin-top:12px;"></div>

        <div style="display:flex; gap:10px; align-items:center;">
            <button type="submit" class="btn-primary-like">Save Settings</button>
            <a href="selfie.php" class="btn-secondary-like btn-link-like">Back</a>
        </div>
    </form>
    <?php } ?>
</div>
<script>
(function(){
    const raceId = document.getElementById('race_id') ? document.getElementById('race_id').value : '';
    const labelInput = document.getElementById('label_color');
    const dataInput = document.getElementById('data_color');
    const nameInput = document.getElementById('name_color');
    const sponsorInput = document.getElementById('sponsor_logo');
    const uploadBtn = document.getElementById('uploadSponsorBtn');
    const uploadStatus = document.getElementById('uploadSponsorStatus');
    const form = document.getElementById('settingsForm');
    const bgInput = document.getElementById('background_color');
    const sponsorThumb = document.getElementById('sponsorThumb');

    async function load(){
        if (!raceId) return;
        try {
            const resp = await fetch('settings.php?get_colors=1&race_id=' + encodeURIComponent(raceId), {cache:'no-store'});
            const js = await resp.json();
            if (js && js.ok) {
                if (js.label_color) labelInput.value = js.label_color;
                if (js.data_color) dataInput.value = js.data_color;
                if (js.name_color) nameInput.value = js.name_color;
                if (js.background_color) bgInput.value = js.background_color;
                if (js.sponsor_logo && sponsorThumb) {
                    sponsorThumb.innerHTML = '<div style="font-size:0.9em; color:#555; margin-bottom:6px;">Current Sponsor Logo</div>'+
                                              '<img src="'+ js.sponsor_logo +'" alt="Sponsor Logo" style="max-height:80px; max-width:100%; border-radius:6px;">';
                }
            }
        } catch(e){}
    }
    async function save(e){
        e.preventDefault();
        if (!raceId) return;
        const fd = new FormData();
        fd.append('save_colors','1');
        fd.append('race_id', raceId);
        fd.append('race_name','');
        fd.append('label_color', labelInput.value);
        fd.append('data_color', dataInput.value);
        fd.append('name_color', nameInput.value);
        fd.append('background_color', bgInput.value);
        await fetch('settings.php', {method:'POST', body: fd});
        alert('Settings saved');
    }
    async function upload(){
        if (!raceId) { uploadStatus.textContent='Select race first'; return; }
        if (!(sponsorInput && sponsorInput.files && sponsorInput.files[0])) { uploadStatus.textContent='Choose a file'; return; }
        uploadStatus.textContent='Uploading...';
        const up = new FormData();
        up.append('upload_sponsor','1');
        up.append('race_id', raceId);
        up.append('sponsor_logo', sponsorInput.files[0]);
        const resp = await fetch('settings.php', {method:'POST', body: up, cache:'no-store'});
        const js = await resp.json().catch(()=>({ok:false}));
        uploadStatus.textContent = (resp.ok && js && js.ok) ? 'Uploaded' : 'Upload failed';
    }
    if (form) form.addEventListener('submit', save);
    if (uploadBtn) uploadBtn.addEventListener('click', upload);
    load();
})();
</script>
</body>
</html>

