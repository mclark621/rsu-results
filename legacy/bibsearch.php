<?php
session_start();
// PHP logic to get values from POST/GET/SESSION
$race_id = isset($_POST['race_id']) ? $_POST['race_id'] : (isset($_GET['race_id']) ? $_GET['race_id'] : (isset($_SESSION['race_id']) ? $_SESSION['race_id'] : null));
$timeout = isset($_POST['timeout']) ? $_POST['timeout'] : (isset($_GET['timeout']) ? $_GET['timeout'] : (isset($_SESSION['timeout']) ? $_SESSION['timeout'] : 15)); // Default timeout to 15
$label_color = isset($_POST['label_color']) ? $_POST['label_color'] : (isset($_GET['label_color']) ? $_GET['label_color'] : '#90D5FF');
$data_color = isset($_POST['data_color']) ? $_POST['data_color'] : (isset($_GET['data_color']) ? $_GET['data_color'] : '#d1842a');
$name_color = isset($_POST['name_color']) ? $_POST['name_color'] : (isset($_GET['name_color']) ? $_GET['name_color'] : '#000000');
$bib = isset($_POST['bib_num']) ? $_POST['bib_num'] : (isset($_GET['bib_num']) ? $_GET['bib_num'] : '');
$name = isset($_POST['runner_name']) ? $_POST['runner_name'] : (isset($_GET['runner_name']) ? $_GET['runner_name'] : '');
$search_type = isset($_POST['search_type']) ? $_POST['search_type'] : (isset($_GET['search_type']) ? $_GET['search_type'] : 'bib');

// Persist core selections into session
if ($race_id) { $_SESSION['race_id'] = $race_id; }
$_SESSION['timeout'] = $timeout;
if (isset($_POST['start_date'])) { $_SESSION['start_date'] = $_POST['start_date']; }
if (isset($_POST['end_date'])) { $_SESSION['end_date'] = $_POST['end_date']; }

// Get race logo if race_id is available
$logo_url = '';
if ($race_id) {
    session_start();
    require('ApiConfig.php');
    require('RunSignupRestClient.class.php');
    
    // Initialize REST client
    $restClient = new RunSignupRestClient(ENDPOINT, PROTOCOL, null, null, null, null, $_SESSION['rsu_access_token']);
    $restClient->setReturnFormat('json');
    
    // Get race information
    $urlPrefix = 'race/' . $race_id;
    $getParms = ['most_recent_events_only' => 'F'];
    $resp = $restClient->callMethod($urlPrefix, 'GET', $getParms, null, true);
    
    if ($resp && isset($resp['race']['logo_url'])) {
        $logo_url = $resp['race']['logo_url'];
    }

    // Load stored colors from SQLite if available
    try {
        $db = new SQLite3(__DIR__ . '/selfie.sqlite');
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
        // ensure sponsor_logo column exists (add only if missing)
        try {
            $colExists = false;
            $ti = $db->query("PRAGMA table_info(color_settings)");
            if ($ti) {
                while ($row = $ti->fetchArray(SQLITE3_ASSOC)) {
                    if (isset($row['name']) && $row['name'] === 'sponsor_logo') { $colExists = true; break; }
                }
            }
            if (!$colExists) {
                $db->exec('ALTER TABLE color_settings ADD COLUMN sponsor_logo TEXT');
            }
            $colExistsBg = false; $ti2 = $db->query("PRAGMA table_info(color_settings)");
            if ($ti2) { while ($row2 = $ti2->fetchArray(SQLITE3_ASSOC)) { if (($row2['name']??'')==='background_color'){ $colExistsBg=true; break; } } }
            if (!$colExistsBg) { $db->exec('ALTER TABLE color_settings ADD COLUMN background_color TEXT'); }
        } catch (Exception $e) { /* ignore */ }
        $stmt = $db->prepare('SELECT label_color, data_color, name_color, sponsor_logo, background_color FROM color_settings WHERE race_id = :race_id');
        $stmt->bindValue(':race_id', $race_id, SQLITE3_TEXT);
        $res = $stmt->execute();
        if ($res) {
            $row = $res->fetchArray(SQLITE3_ASSOC);
            if ($row) {
                if (!isset($_POST['label_color']) && !isset($_GET['label_color'])) {
                    $label_color = $row['label_color'] ?: $label_color;
                }
                if (!isset($_POST['data_color']) && !isset($_GET['data_color'])) {
                    $data_color = $row['data_color'] ?: $data_color;
                }
                if (!isset($_POST['name_color']) && !isset($_GET['name_color'])) {
                    $name_color = $row['name_color'] ?: $name_color;
                }
                if (isset($row['sponsor_logo'])) { $sponsor_logo = $row['sponsor_logo']; }
                if (isset($row['background_color'])) { $background_color = $row['background_color']; }
            }
        }
        if (isset($res) && $res) { $res->finalize(); }
        $stmt = null;
        $db->close();
    } catch (Exception $e) {
        // ignore persistence errors for UI flow
    }
}

// Name search selection is handled in results.php; no interception here
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>Search Results - Bay City Timing & Events</title>
    <!-- External stylesheet (fallback to inline styles if not loading) -->
    <link rel="stylesheet" href="./assets/style/stylesheets.css?v=<?php echo time(); ?>" onerror="console.log('External stylesheet failed to load, using inline styles')">
    <style>
        /* Comprehensive responsive styles */
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        
        body {
            background-color: #f4f7f6;
            margin: 0;
            padding: 0;
            overflow-x: hidden;
        }
        
        .form-container {
            width: 100%;
            max-width: 550px;
            max-height: 100vh;
            margin: 0 auto;
            padding: 15px 20px;
            background-color: #ffffff;
            border: 1px solid #e0e0e0;
            border-radius: 12px;
            box-shadow: 0 8px 16px rgba(0, 0, 0, 0.1);
            display: flex;
            flex-direction: column;
            overflow-y: auto;
        }
        
        .stylish-form {
            display: flex;
            flex-direction: column;
            gap: 12px;
            flex: 1;
            min-height: 0;
        }
        
        /* Stylish notification popup */
        .notification-popup {
            position: fixed;
            top: 20px;
            left: 50%;
            transform: translateX(-50%) translateY(-100px);
            background: linear-gradient(135deg, #ff8c00 0%, #ff6b00 100%);
            color: white;
            padding: 18px 28px;
            border-radius: 12px;
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
            z-index: 10000;
            opacity: 0;
            transition: all 0.4s cubic-bezier(0.68, -0.55, 0.265, 1.55);
            display: flex;
            align-items: center;
            gap: 12px;
            max-width: 90%;
            font-weight: 600;
            font-size: 16px;
        }
        
        .notification-popup.show {
            transform: translateX(-50%) translateY(0);
            opacity: 1;
        }
        
        .notification-popup .icon {
            font-size: 24px;
            flex-shrink: 0;
        }
        
        .notification-popup .message {
            flex: 1;
        }
        
        @media (max-width: 767px) {
            .notification-popup {
                top: 10px;
                padding: 14px 20px;
                font-size: 14px;
                max-width: 95%;
            }
        }
        
        .logo {
            text-align: center;
            margin-bottom: 10px;
        }
        
        .logo img {
            max-width: 100%;
            height: auto;
            max-height: 80px;
        }
        
        .stylish-form label {
            font-size: 1.1em;
            font-weight: 600;
            color: #444;
            margin-bottom: 5px;
            display: block;
        }
        
        .stylish-form input[type="text"], .stylish-form select {
            width: 100%;
            padding: 10px;
            font-size: 1em;
            border: 2px solid #ccc;
            border-radius: 8px;
            background-color: #f9f9f9;
            transition: all 0.3s ease;
        }
        
        .stylish-form input[type="text"]:focus, .stylish-form select:focus {
            border-color: #00bcd4;
            box-shadow: 0 0 8px rgba(0, 188, 212, 0.4);
            outline: none;
            background-color: #fff;
        }
        
        .stylish-form input[type="submit"] {
            background-color: #ff8c00;
            color: white;
            padding: 12px 25px;
            font-size: 1em;
            font-weight: bold;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            text-transform: uppercase;
            letter-spacing: 1px;
            transition: background-color 0.3s ease, transform 0.2s ease, box-shadow 0.3s ease;
            margin-top: 8px;
        }
        
        .stylish-form input[type="submit"]:hover {
            background-color: #e67e00;
            transform: translateY(-2px);
            box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2);
        }
        
        .keypad {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 8px;
            margin-top: 10px;
        }
        
        .keypad button {
            background-color: #f0f0f0;
            color: #444;
            border: 1px solid #ccc;
            border-radius: 6px;
            font-size: 1.3em;
            font-weight: bold;
            padding: 10px 0;
            cursor: pointer;
            transition: background-color 0.2s, transform 0.1s;
        }
        
        .keypad button:hover {
            background-color: #e0e0e0;
        }
        
        .keypad button:active {
            transform: scale(0.98);
        }
        
        .keypad .key-clear {
            background-color: #ff4d4d;
            color: white;
        }
        
        .keypad .key-clear:hover {
            background-color: #e60000;
        }
        
        .keypad .key-delete {
            background-color: #ffa366;
            color: white;
        }
        
        .keypad .key-delete:hover {
            background-color: #ff8c00;
        }
        
        .search-type-container {
            margin-bottom: 8px;
        }
        
        .search-input-group {
            margin-bottom: 8px;
        }
        
        /* Race logo container - centered at top */
        .race-logo-container {
            text-align: center;
            margin: 8px 0 12px 0;
        }
        
        /* Race logo responsive styling */
        .race-logo {
            max-width: 250px;
            max-height: 80px;
            width: auto;
            height: auto;
            border-radius: 8px;
            transition: transform 0.3s ease;
        }
        
        .race-logo:hover {
            transform: scale(1.05);
        }
        
        /* BCT logo container - at bottom */
        .bct-logo-container {
            text-align: center;
            margin-top: 10px;
            padding-top: 10px;
            border-top: 1px solid #e0e0e0;
        }
        
        .bct-logo {
            max-width: 150px;
            max-height: 60px;
            width: auto;
            height: auto;
            opacity: 0.8;
            transition: opacity 0.3s ease;
        }
        
        .bct-logo:hover {
            opacity: 1;
        }
        
        /* Responsive Design */
        @media (min-width: 1200px) {
            .form-container {
                max-width: 600px;
                max-height: 100vh;
                margin: 0 auto;
                padding: 15px 25px;
            }
            .logo img {
                max-height: 80px;
            }
            .race-logo {
                max-width: 250px;
                max-height: 100px;
            }
            .bct-logo {
                max-width: 150px;
                max-height: 60px;
            }
            .stylish-form label {
                font-size: 1em;
            }
            .stylish-form input[type="text"], .stylish-form select {
                padding: 10px;
                font-size: 1em;
            }
            .stylish-form input[type="submit"] {
                padding: 12px 25px;
                font-size: 1em;
            }
            .keypad {
                gap: 8px;
                margin-top: 10px;
            }
            .keypad button {
                font-size: 1.3em;
                padding: 10px 0;
            }
        }
        
        @media (min-width: 768px) and (max-width: 1199px) {
            .form-container {
                max-width: 500px;
                max-height: 100vh;
                margin: 0 auto;
                padding: 15px 20px;
            }
            .logo img {
                max-height: 70px;
            }
            .race-logo {
                max-width: 220px;
                max-height: 80px;
            }
            .bct-logo {
                max-width: 140px;
                max-height: 55px;
            }
            .stylish-form label {
                font-size: 1em;
            }
            .stylish-form input[type="text"], .stylish-form select {
                padding: 10px;
                font-size: 1em;
            }
            .stylish-form input[type="submit"] {
                padding: 12px 25px;
                font-size: 1em;
            }
            .keypad {
                gap: 8px;
                margin-top: 10px;
            }
            .keypad button {
                font-size: 1.3em;
                padding: 10px 0;
            }
        }
        
        @media (max-width: 767px) {
            body {
                padding: 0;
            }
            .form-container {
                max-width: 100%;
                max-height: none;
                margin: 0 auto;
                padding: 20px 15px;
                border-radius: 8px;
                overflow-y: visible;
            }
            .logo {
                margin-bottom: 15px;
            }
            .logo img {
                max-height: 80px;
            }
            .race-logo {
                max-width: 250px;
                max-height: 100px;
            }
            .bct-logo {
                max-width: 150px;
                max-height: 60px;
            }
            .stylish-form label {
                font-size: 1em;
                margin-bottom: 8px;
            }
            .stylish-form input[type="text"], .stylish-form select {
                padding: 12px;
                font-size: 1em;
                border-radius: 6px;
            }
            .stylish-form input[type="submit"] {
                padding: 16px 25px;
                font-size: 1.1em;
                border-radius: 6px;
                letter-spacing: 0.5px;
            }
            .keypad {
                gap: 10px;
                margin-top: 15px;
            }
            .keypad button {
                font-size: 1.5em;
                padding: 15px 0;
                border-radius: 6px;
            }
        }
        
        @media (max-width: 480px) {
            body {
                padding: 0;
            }
            .form-container {
                max-height: none;
                margin: 0 auto;
                padding: 18px 12px;
                border-radius: 6px;
                overflow-y: visible;
            }
            .logo {
                margin-bottom: 12px;
            }
            .logo img {
                max-height: 70px;
            }
            .race-logo {
                max-width: 220px;
                max-height: 90px;
            }
            .bct-logo {
                max-width: 140px;
                max-height: 55px;
            }
            .stylish-form label {
                font-size: 0.95em;
                margin-bottom: 6px;
            }
            .stylish-form input[type="text"], .stylish-form select {
                padding: 11px;
                font-size: 0.95em;
            }
            .stylish-form input[type="submit"] {
                padding: 14px 22px;
                font-size: 1em;
                letter-spacing: 0.3px;
            }
            .keypad {
                gap: 8px;
                margin-top: 12px;
            }
            .keypad button {
                font-size: 1.3em;
                padding: 12px 0;
                border-radius: 5px;
            }
        }
        
        @media (max-width: 767px) and (orientation: landscape) {
            .form-container {
                max-height: none;
                margin: 0 auto;
                padding: 12px 15px;
                overflow-y: visible;
            }
            .logo {
                margin-bottom: 8px;
            }
            .logo img {
                max-height: 60px;
            }
            .race-logo {
                max-width: 200px;
                max-height: 70px;
            }
            .bct-logo {
                max-width: 120px;
                max-height: 50px;
            }
            .keypad {
                gap: 8px;
                margin-top: 10px;
            }
            .keypad button {
                font-size: 1.3em;
                padding: 10px 0;
            }
        }
    </style>
</head>
<body<?php if (!empty($background_color)) { echo ' style="background-color: ' . htmlspecialchars($background_color) . '"'; } ?>>
    <div class="form-container">
        <?php if (!empty($logo_url) || !empty($sponsor_logo)): ?>
        <div class="race-logo-container" style="display:flex; gap:8px; align-items:center; justify-content:center; margin:4px 0;">
            <?php if (!empty($logo_url)) { ?>
                <img src="<?php echo htmlspecialchars($logo_url); ?>" alt="Race Logo" class="race-logo">
            <?php } ?>
            <?php if (!empty($sponsor_logo)) { ?>
                <img src="<?php echo htmlspecialchars($sponsor_logo); ?>" alt="Sponsor Logo" class="race-logo" style="max-height:80px;">
            <?php } ?>
        </div>
        <?php endif; ?>
        <form class="stylish-form" action="results.php" method="POST">
            <!-- Search Type Selection (Radio Buttons) -->
            <div class="search-type-container">
                <div style="display:flex; gap:16px; align-items:center; margin-top:4px;">
                    <label>
                        <input type="radio" name="search_type" value="bib" <?php echo $search_type === 'bib' ? 'checked' : ''; ?>>
                        Bib Number
                    </label>
                    <label>
                        <input type="radio" name="search_type" value="name" <?php echo $search_type === 'name' ? 'checked' : ''; ?>>
                        Runner Name
                    </label>
                </div>
            </div>

            <!-- Bib Number Input -->
            <div id="bib-search" class="search-input-group">
                <input type="text" name="bib_num" id="bib_num" placeholder="Type bib number" value="<?php echo htmlspecialchars($bib); ?>" autofocus inputmode="numeric" pattern="[0-9]*" autocomplete="off">
                
                <div class="keypad">
                    <button type="button" onclick="addDigit(7)">7</button>
                    <button type="button" onclick="addDigit(8)">8</button>
                    <button type="button" onclick="addDigit(9)">9</button>
                    <button type="button" onclick="addDigit(4)">4</button>
                    <button type="button" onclick="addDigit(5)">5</button>
                    <button type="button" onclick="addDigit(6)">6</button>
                    <button type="button" onclick="addDigit(1)">1</button>
                    <button type="button" onclick="addDigit(2)">2</button>
                    <button type="button" onclick="addDigit(3)">3</button>
                    <button type="button" class="key-clear" onclick="clearInput()">CLR</button>
                    <button type="button" onclick="addDigit(0)">0</button>
                    <button type="button" class="key-delete" onclick="deleteDigit()">DEL</button>
                </div>
            </div>

            <!-- Name Search Input -->
            <div id="name-search" class="search-input-group" style="display: none;">
                <input type="text" name="runner_name" id="runner_name" placeholder="Type name" value="<?php echo htmlspecialchars($name); ?>">
            </div>

            <input type="hidden" name="race_id" value="<?php echo htmlspecialchars($race_id); ?>">
            <input type="hidden" name="timeout" value="<?php echo htmlspecialchars($timeout); ?>">
            <input type="hidden" name="label_color" value="<?php echo htmlspecialchars($label_color); ?>">
            <input type="hidden" name="data_color" value="<?php echo htmlspecialchars($data_color); ?>">
            <input type="hidden" name="name_color" value="<?php echo htmlspecialchars($name_color); ?>">
            <input type="hidden" name="start_date" value="<?php echo htmlspecialchars(isset($_SESSION['start_date']) ? $_SESSION['start_date'] : date('Y-m-d')); ?>">
            <input type="hidden" name="end_date" value="<?php echo htmlspecialchars(isset($_SESSION['end_date']) ? $_SESSION['end_date'] : date('Y-m-d')); ?>">
            
            <input type="submit" value="Find Results">
        </form>
        
        <div class="bct-logo-container">
            <img src="assets/img/bctlogo.png" alt="Bay City Timing & Events Logo" class="bct-logo">
        </div>
    </div>

    <script>
        const searchTypeRadios = document.querySelectorAll('input[name="search_type"]');
        const bibSearchGroup = document.getElementById('bib-search');
        const nameSearchGroup = document.getElementById('name-search');
        const bibInput = document.getElementById('bib_num');
        const nameInput = document.getElementById('runner_name');
        const form = document.querySelector('.stylish-form');

        function getSelectedType() {
            let sel = 'bib';
            searchTypeRadios.forEach(r => { if (r.checked) sel = r.value; });
            return sel;
        }

        // Helper function to focus input and set cursor to end
        function focusInputAtEnd(input) {
            if (input) {
                input.focus();
                // Set cursor to end of text
                const len = input.value.length;
                if (input.setSelectionRange) {
                    input.setSelectionRange(len, len);
                } else if (input.createTextRange) {
                    const range = input.createTextRange();
                    range.collapse(true);
                    range.moveEnd('character', len);
                    range.moveStart('character', len);
                    range.select();
                }
            }
        }

        function toggleSearchInputs() {
            const searchType = getSelectedType();
            if (searchType === 'bib') {
                bibSearchGroup.style.display = 'block';
                nameSearchGroup.style.display = 'none';
                bibInput.placeholder = 'Type bib number';
                focusInputAtEnd(bibInput);
            } else {
                bibSearchGroup.style.display = 'none';
                nameSearchGroup.style.display = 'block';
                nameInput.placeholder = 'Type name';
                focusInputAtEnd(nameInput);
            }
        }

        searchTypeRadios.forEach(r => r.addEventListener('change', toggleSearchInputs));

        function addDigit(digit) {
            if (getSelectedType() === 'bib') {
                bibInput.value += digit;
            }
        }

        function clearInput() {
            if (getSelectedType() === 'bib') {
                bibInput.value = '';
            } else {
                nameInput.value = '';
            }
        }

        function deleteDigit() {
            if (getSelectedType() === 'bib') {
                bibInput.value = bibInput.value.slice(0, -1);
            } else {
                nameInput.value = nameInput.value.slice(0, -1);
            }
        }

        // Function to submit form (triggers validation)
        function submitForm() {
            if (form) {
                // Use requestSubmit() if available (triggers submit event and validation)
                if (typeof form.requestSubmit === 'function') {
                    form.requestSubmit();
                } else {
                    // Fallback: click the submit button to trigger validation
                    const submitBtn = form.querySelector('input[type="submit"]');
                    if (submitBtn) {
                        submitBtn.click();
                    } else {
                        form.submit();
                    }
                }
            }
        }

        // Restrict bib input to digits only (typing, paste, programmatic)
        if (bibInput) {
            bibInput.addEventListener('keypress', function(e) {
                // Allow Enter key (keyCode 13) to submit the form
                if (e.keyCode === 13 || e.which === 13) {
                    e.preventDefault();
                    submitForm();
                    return;
                }
                const ch = String.fromCharCode(e.which || e.keyCode);
                if (!/[0-9]/.test(ch)) {
                    e.preventDefault();
                }
            });
            bibInput.addEventListener('paste', function(e) {
                const data = (e.clipboardData || window.clipboardData).getData('text');
                if (!/^\d+$/.test(data)) {
                    e.preventDefault();
                }
            });
            bibInput.addEventListener('input', function() {
                this.value = this.value.replace(/\D+/g, '');
            });
        }
        
        // Handle Enter key for name input
        if (nameInput) {
            nameInput.addEventListener('keypress', function(e) {
                if (e.keyCode === 13 || e.which === 13) {
                    e.preventDefault();
                    submitForm();
                }
            });
        }

        // Show stylish notification popup
        function showNotification(message) {
            // Remove any existing notification
            const existing = document.querySelector('.notification-popup');
            if (existing) {
                existing.remove();
            }
            
            // Create notification element
            const notification = document.createElement('div');
            notification.className = 'notification-popup';
            notification.innerHTML = '<span class="icon">⚠️</span><span class="message">' + message + '</span>';
            
            document.body.appendChild(notification);
            
            // Trigger animation
            setTimeout(function() {
                notification.classList.add('show');
            }, 10);
            
            // Auto-hide after 3 seconds
            setTimeout(function() {
                notification.classList.remove('show');
                setTimeout(function() {
                    if (notification.parentNode) {
                        notification.parentNode.removeChild(notification);
                    }
                }, 400);
            }, 3000);
        }

        // Form validation - prevent submit if search input is blank
        if (form) {
            form.addEventListener('submit', function(e) {
                const searchType = getSelectedType();
                let isValid = false;
                
                if (searchType === 'bib') {
                    const bibValue = bibInput.value.trim();
                    if (bibValue === '') {
                        e.preventDefault();
                        showNotification('Please enter a bib number');
                        bibInput.focus();
                        return false;
                    }
                    isValid = true;
                } else if (searchType === 'name') {
                    const nameValue = nameInput.value.trim();
                    if (nameValue === '') {
                        e.preventDefault();
                        showNotification('Please enter a runner name');
                        nameInput.focus();
                        return false;
                    }
                    isValid = true;
                }
                
                return isValid;
            });
        }

        // Initialize the form based on current search type
        document.addEventListener('DOMContentLoaded', function() {
            toggleSearchInputs();
        });
    </script>
<script>
// Open Settings: Win/Linux Ctrl+Alt+S, macOS Option+Command+S
(function(){
  var lastTs = 0;
  function handler(e){
    var t = e.target;
    if (t && ((t.tagName === 'INPUT') || (t.tagName === 'TEXTAREA') || t.isContentEditable)) return;
    var isMacCombo = e.metaKey && e.altKey && (e.code === 'KeyS');
    var isWinCombo = e.ctrlKey && e.altKey && (e.code === 'KeyS');
    if (!(isMacCombo || isWinCombo)) return;
    var now = Date.now();
    if (now - lastTs < 500 || e.repeat) return;
    lastTs = now;
    e.preventDefault();
    var raceId = <?php echo json_encode($race_id); ?>;
    if (!raceId) { return; }
    window.location.href = 'settings.php?race_id=' + encodeURIComponent(raceId);
  }
  document.addEventListener('keydown', handler, false);
})();
</script>
</body>
</html>