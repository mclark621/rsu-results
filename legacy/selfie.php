<?php
session_start();
// NOTE: Bib numbers should have been set up for this event already from
// 1 to RESULTS_TEST1_NUM_PARTICIPANTS

// NOTE: Copy ApiConfig.sample.php to ApiConfig.php and modify
// Get up some config
require('ApiConfig.php');

require('RunSignupRestClient.class.php');

// Persist incoming dates/timeouts into session
if (isset($_POST['start_date'])) { $_SESSION['start_date'] = $_POST['start_date']; }
if (isset($_POST['end_date'])) { $_SESSION['end_date'] = $_POST['end_date']; }
if (isset($_POST['timeout'])) { $_SESSION['timeout'] = (int)$_POST['timeout']; }


// Check if there are timer settings
$loggedIn = false;
if (defined('TIMER_API_KEY') && TIMER_API_KEY && defined('TIMER_API_SECRET') && TIMER_API_SECRET)
{
	// Set up API
//	$restClient = new RunSignupRestClient(ENDPOINT, PROTOCOL, TIMER_API_KEY, TIMER_API_SECRET);
}
$restClient = new RunSignupRestClient(ENDPOINT, PROTOCOL, null, null, null, null, $_SESSION['rsu_access_token']);

// Set response format
$restClient->setReturnFormat('json');
// Set up URL prefix
$urlPrefix = 'races/';
// Get race information
$getParms['only_races_with_results'] = 'T';
$getParms['start_date'] = isset($_SESSION['start_date']) ? $_SESSION['start_date'] : date('Y-m-d');
$getParms['end_date'] = isset($_SESSION['end_date']) ? $_SESSION['end_date'] : date('Y-m-d');


$resp = $restClient->callMethod($urlPrefix, 'GET', $getParms, null, true);
if (!$resp) {
    die("Request failed.\n" . $restClient->lastRawResponse);
}
if (isset($resp['error'])) {
    die(print_r($resp, 1) . PHP_EOL);
}

// Initialize timeout variable
$timeout = isset($_SESSION['timeout']) ? (int)$_SESSION['timeout'] : (isset($_POST['timeout']) ? (int)$_POST['timeout'] : 20);

// Check if races are available
if (!isset($resp['races']) || empty($resp['races'])) {
    die("No races found for the selected date range.\n");
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Select Event - Bay City Timing & Events</title>
    <link rel="stylesheet" href="assets/style/stylesheets.css">
</head>
<body>
    <div class="form-container">
        <div class="logo">
            <img src="assets/img/bctlogo.png" alt="Bay City Timing & Events Logo">
        </div>
        <form class="stylish-form" action="bibsearch.php" method="POST">
            <label for="race_id">Select an Event:</label>
            <select name="race_id" id="race_id" required>
                <option value="">-- Please select an event --</option>
                <?php foreach ($resp['races'] as $race): ?>
                    <option value="<?php echo htmlspecialchars($race['race']['race_id']); ?>">
                        <?php echo htmlspecialchars($race['race']['name']); ?>
                    </option>
                <?php endforeach; ?>
            </select>
            <div style="margin-top:10px; display:flex; gap:10px; align-items:center;">
                <button type="button" id="openSettingsBtn" style="background-color:#ff8c00; color:#fff; padding:10px 14px; font-weight:bold; border:none; border-radius:8px; cursor:pointer; letter-spacing:0.5px; display:none; align-items:center; gap:8px;">
                    <span aria-hidden="true" style="font-size:18px; line-height:1;">⚙</span>
                    <span>Settings</span>
                </button>
            </div>
            
            <label for="timeout-select">Timeout (Seconds):</label>
            <select name="timeout" id="timeout-select">
                <?php
                // List of available timeout options
                $timeout_options = [10, 15, 20, 25, 30, 45];
                
                foreach ($timeout_options as $option) {
                    $selected = ($timeout == $option) ? 'selected' : '';
                    echo "<option value=\"{$option}\" {$selected}>{$option}</option>";
                }
                ?>
            </select>
            <input type="hidden" name="start_date" value="<?php echo htmlspecialchars(isset($_SESSION['start_date']) ? $_SESSION['start_date'] : date('Y-m-d')); ?>">
            <input type="hidden" name="end_date" value="<?php echo htmlspecialchars(isset($_SESSION['end_date']) ? $_SESSION['end_date'] : date('Y-m-d')); ?>">
            
            

            <input type="submit" value="Select Race">
        </form>
    </div>
<script>
// Open Settings from any page: Win/Linux Ctrl+Alt+S, macOS Option+Command+S
(function(){
  var lastTs = 0;
  var raceSelect = document.getElementById('race_id');
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
    var raceId = raceSelect ? raceSelect.value : '';
    if (!raceId) { return; }
    window.location.href = 'settings.php?race_id=' + encodeURIComponent(raceId);
  }
  document.addEventListener('keydown', handler, false);
})();
</script>
</body>
<script>
    (function(){
        const form = document.querySelector('.stylish-form');
        if (!form) return;

        const raceSelect = document.getElementById('race_id');
        const openSettingsBtn = document.getElementById('openSettingsBtn');

        function updateSettingsVisibility(){
            if (!openSettingsBtn) return;
            const hasRace = raceSelect && raceSelect.value && raceSelect.value !== '';
            openSettingsBtn.style.display = hasRace ? 'inline-flex' : 'none';
        }

        if (openSettingsBtn) {
            openSettingsBtn.addEventListener('click', function(){
                const raceId = raceSelect ? raceSelect.value : '';
                if (!raceId) { return; }
                window.location.href = 'settings.php?race_id=' + encodeURIComponent(raceId);
            });
        }

        if (openSettingsBtn) { openSettingsBtn.style.display = 'none'; }
        if (raceSelect) {
            raceSelect.addEventListener('change', updateSettingsVisibility);
        }
        // Defer a tick to allow browsers that auto-restore form state; then evaluate.
        setTimeout(updateSettingsVisibility, 0);

        // Settings button opens settings page for selected race
        if (raceSelect && openSettingsBtn) {
            openSettingsBtn.addEventListener('click', function(){
                const raceId = raceSelect.value;
                if (!raceId) { alert('Please select a race first.'); return; }
                window.location.href = 'settings.php?race_id=' + encodeURIComponent(raceId);
            });
        }

        // Plain submit to bibsearch
    })();
</script>
</html>
<?php
// Logout if logged in
if ($loggedIn) {
    $restClient->logout();
}
?>