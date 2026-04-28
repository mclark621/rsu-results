<?php
session_start();
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
if(isset($_SESSION['rsu_access_token']) && $_SESSION['rsu_access_token'] != '' && $_SESSION['rsu_access_token'] != null) {
    $rsu_access_token = $_SESSION['rsu_access_token'];
    $rsu_api_key = null;
    $rsu_api_secret = null;
} else {
    $rsu_access_token = null;
    $rsu_api_key = getenv('RSU_API_KEY');
    $rsu_api_secret = getenv('RSU_API_SECRET');
}
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $race_id = isset($_POST['race_id']) ? $_POST['race_id'] : (isset($_SESSION['race_id']) ? $_SESSION['race_id'] : null);
    $timeout = isset($_POST['timeout']) ? $_POST['timeout'] : (isset($_SESSION['timeout']) ? $_SESSION['timeout'] : '20');
    $search_type = isset($_POST['search_type']) ? $_POST['search_type'] : 'bib';
    $bib_num = isset($_POST['bib_num']) && $_POST['bib_num'] !== '' ? $_POST['bib_num'] : null;
    $runner_name = isset($_POST['runner_name']) && $_POST['runner_name'] !== '' ? $_POST['runner_name'] : '';
    
    // Check if this is a bib selection from multi-result (has bib_num but no runner_name indicates selection from name search results)
    $isBibSelectionFromMultiResult = ($bib_num !== null && $runner_name === '' && isset($_SESSION['search_type']) && $_SESSION['search_type'] === 'name');
    
    // Store search type and values in session
    // BUT: if selecting a bib from multi-result, preserve the original name search type in session
    if ($search_type === 'name' && $runner_name !== '') {
        // New name search - update session
        $_SESSION['search_type'] = $search_type;
        $bib_num = null;
        $_SESSION['runner_name'] = $runner_name;
        unset($_SESSION['bib_num']);
    } else if ($search_type === 'bib' && $bib_num !== null && $bib_num !== '' && !$isBibSelectionFromMultiResult) {
        // New bib search - update session
        $_SESSION['search_type'] = $search_type;
        $runner_name = '';
        $_SESSION['bib_num'] = $bib_num;
        unset($_SESSION['runner_name']);
    } else if ($isBibSelectionFromMultiResult) {
        // Bib selected from multi-result - use bib for this search but DON'T update session search_type
        // Keep the session search_type as 'name' so redirect goes back to name search
        $runner_name = '';
        // Don't update $_SESSION['search_type'] - keep it as 'name'
        // Don't clear $_SESSION['runner_name'] - keep it for redirect
    }
    $label_color = isset($_POST['label_color']) ? $_POST['label_color'] : '#90D5FF';
    $data_color = isset($_POST['data_color']) ? $_POST['data_color'] : '#d1842a';
    $name_color = isset($_POST['name_color']) ? $_POST['name_color'] : '#000000';
    if ($race_id) { $_SESSION['race_id'] = $race_id; }
    $_SESSION['timeout'] = $timeout;
    $rsu_api_key = null;
    $rsu_api_secret = null;
} else {
    $race_id = isset($_GET['race_id']) ? $_GET['race_id'] : (isset($_SESSION['race_id']) ? $_SESSION['race_id'] : null);
    $timeout = isset($_SESSION['timeout']) ? (string)$_SESSION['timeout'] : "20";
    $bib_num = isset($_GET['bib_num']) ? $_GET['bib_num'] : (isset($_SESSION['bib_num']) ? $_SESSION['bib_num'] : null);
    $runner_name = isset($_GET['runner_name']) ? $_GET['runner_name'] : (isset($_SESSION['runner_name']) ? $_SESSION['runner_name'] : '');
    $label_color = isset($_GET['label_color']) ? $_GET['label_color'] : '#90D5FF';
    $data_color = isset($_GET['data_color']) ? $_GET['data_color'] : '#d1842a';
    $name_color = isset($_GET['name_color']) ? $_GET['name_color'] : '#000000';
}
// Include required files
require('ApiConfig.php');
require('RunSignupRestClient.class.php');

// Initialize REST client
$restClient = new RunSignupRestClient(ENDPOINT, PROTOCOL, $rsu_api_key, $rsu_api_secret, null, null, $rsu_access_token);
$restClient->setReturnFormat('json');

// Get race information
$urlPrefix = 'race/' . $race_id;
// If a runner name was provided, search by last_name; otherwise search by bib_num
if (isset($runner_name) && $runner_name !== '') {
    $getParms = [
        'most_recent_events_only' => 'F',
        'last_name' => $runner_name,
        'include_division_finishers' => 'T',
        'include_total_finishers' => 'T'
    ];
} else {
    $getParms = [
        'most_recent_events_only' => 'F',
        'bib_num' => $bib_num,
        'include_division_finishers' => 'T',
        'include_total_finishers' => 'T'
    ];
}

$resp = $restClient->callMethod($urlPrefix, 'GET', $getParms, null, true);
$logo_url = $resp['race']['logo_url'] ?? '';
$race_display_name = isset($resp['race']['name']) ? $resp['race']['name'] : '';
$sponsor_logo = '';
$background_color = '';

// Build canonical share URL and Open Graph values (best-effort)
$scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
$host = isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'localhost';
$basePath = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/results.php'), '/');
$share_params = [ 'race_id' => $race_id ];
if (!empty($bib_num)) {
    $share_params['bib_num'] = (string)$bib_num;
    $share_params['search_type'] = 'bib';
} elseif (!empty($runner_name)) {
    $share_params['runner_name'] = (string)$runner_name;
    $share_params['search_type'] = 'name';
}
$share_query = http_build_query($share_params);
$share_url = $scheme . '://' . $host . $basePath . '/results.php' . ($share_query ? ('?' . $share_query) : '');

$primary_name = '';
if (!empty($race_names)) {
    $firstKey = array_key_first($race_names);
    $primary_name = trim(($first_name[$firstKey] ?? '') . ' ' . ($last_name[$firstKey] ?? ''));
}
$og_title = trim(($primary_name !== '' ? ($primary_name . ' • ') : '') . ($race_display_name ?: 'Race Results'));
$og_desc = '';
if (!empty($race_names)) {
    $firstKey = array_key_first($race_names);
    $og_desc = 'Finish Time: ' . (($chip_time[$firstKey] ?? '') ?: '-') . ' • Bib: ' . (($bib_num ?? '') ?: '-') . ' • ' . ($race_display_name ?: '');
} else {
    $og_desc = 'View race results.';
}
$og_image = '';
if (!empty($sponsor_logo)) { $og_image = $sponsor_logo; }
elseif (!empty($logo_url)) { $og_image = $logo_url; }
else { $og_image = $scheme . '://' . $host . $basePath . '/assets/img/bctlogo.png'; }

// Load stored colors if not supplied (read-only) (DB is stored in the same directory as the script)Once Again
try {
    $db = new SQLite3(__DIR__ . '/selfie.sqlite');
    $db->exec('CREATE TABLE IF NOT EXISTS color_settings (
        race_id TEXT PRIMARY KEY,
        race_name TEXT,
        label_color TEXT,
        data_color TEXT,
        name_color TEXT,
        sponsor_logo TEXT,
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
    } catch (Exception $e) { /* ignore */ }
    if ((!isset($_POST['label_color']) && !isset($_GET['label_color'])) ||
        (!isset($_POST['data_color']) && !isset($_GET['data_color'])) ||
        (!isset($_POST['name_color']) && !isset($_GET['name_color']))) {
        $sel = $db->prepare('SELECT label_color, data_color, name_color, sponsor_logo, background_color FROM color_settings WHERE race_id = :race_id');
        $sel->bindValue(':race_id', $race_id, SQLITE3_TEXT);
        $r = $sel->execute();
        if ($r) {
            $row = $r->fetchArray(SQLITE3_ASSOC);
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
            $r->finalize();
        }
        $sel = null;
    }
    // Always attempt to read sponsor_logo/background even if colors came from POST/GET
    if ($sponsor_logo === '' || $background_color === '') {
        $sel2 = $db->prepare('SELECT sponsor_logo, background_color FROM color_settings WHERE race_id = :race_id');
        $sel2->bindValue(':race_id', $race_id, SQLITE3_TEXT);
        $r2 = $sel2->execute();
        if ($r2) {
            $row2 = $r2->fetchArray(SQLITE3_ASSOC);
            if ($row2) {
                if (isset($row2['sponsor_logo']) && $sponsor_logo==='') { $sponsor_logo = $row2['sponsor_logo']; }
                if (isset($row2['background_color']) && $background_color==='') { $background_color = $row2['background_color']; }
            }
            $r2->finalize();
        }
        $sel2 = null;
    }
    $db->close();
} catch (Exception $e) {
    // ignore persistence errors
}

// Initialize result arrays
$first_name = [];
$last_name = [];
$chip_time = [];
$pace = [];
$place = [];
$finishers = [];
$division_finishers = [];
$gender_finishers = [];
$division_place = [];
$division_placement_id = [];
$division_id = [];
$gender_place = [];
$gender = [];
$results_headers = [];
$race_names = [];

$previous_race_event_days_id = 0;
$searchingByName = isset($runner_name) && $runner_name !== '';
$candidates = [];
// Process race events
foreach ($resp['race']['events'] as $tmp) {
    $start_time = strtotime($tmp['start_time']);
    $right_now = time();
    
    // Skip future events
    if ($start_time > $right_now) {
        continue;
    }
    
    // Break if we've moved to a different race day
    if ($previous_race_event_days_id != 0 && 
        $previous_race_event_days_id != $tmp['race_event_days_id'] && 
        $start_time < $right_now) {
        break;
    }
    
    $previous_race_event_days_id = $tmp['race_event_days_id'];
    $getParms['event_id'] = $tmp['event_id'];
    $urlPrefixResult = 'race/' . $race_id . '/results/get-results';
    $result = $restClient->callMethod($urlPrefixResult, 'GET', $getParms, null, true);
    
    // Process results if available (defensive guards)
    $hasSets = isset($result) && isset($result['individual_results_sets']) && is_array($result['individual_results_sets']) && count($result['individual_results_sets']) > 0;
    $hasFirstResults = $hasSets && isset($result['individual_results_sets'][0]['results']) && is_array($result['individual_results_sets'][0]['results']) && count($result['individual_results_sets'][0]['results']) > 0;
    if ($hasSets && $hasFirstResults) {
        
        $race_name = $tmp['name'];
        $race_names[$race_name] = str_replace(" ", "_", $race_name);
        
        // Get basic result data
        $result_data = $result['individual_results_sets'][0]['results'][0];
        // When searching by name, collect all matching candidates across sets
        if ($searchingByName && $hasSets) {
            foreach ($result['individual_results_sets'] as $set) {
                $eventName = isset($set['event_name']) ? $set['event_name'] : $tmp['name'];
                if (isset($set['results']) && is_array($set['results']) && !empty($set['results'])) {
                    foreach ($set['results'] as $row) {
                        $candidates[] = [
                            'bib' => isset($row['bib']) ? $row['bib'] : '',
                            'first_name' => isset($row['first_name']) ? $row['first_name'] : '',
                            'last_name' => isset($row['last_name']) ? $row['last_name'] : '',
                            'gender' => isset($row['gender']) ? $row['gender'] : '',
                            'age' => isset($row['age']) ? $row['age'] : '',
                            'city' => isset($row['city']) ? $row['city'] : '',
                            'state' => isset($row['state']) ? $row['state'] : '',
                            'event' => $eventName
                        ];
                    }
                }
            }
        }
        $first_name[$race_name] = strtoupper($result_data['first_name']);
        $last_name[$race_name] = strtoupper($result_data['last_name']);
        $bib_num = $result_data['bib'];
        $chip_time[$race_name] = explode(".", $result_data['chip_time'])[0];
        $pace[$race_name] = $result_data['pace'];
        $gender[$race_name] = $result_data['gender'] ?? '';
        $place[$race_name] = $result_data['place'];
        $finishers[$race_name] = $result['individual_results_sets'][0]['num_finishers'];
        $division_finishers[$race_name] = $result['individual_results_sets'][0]['num_division_finishers'];
        $results_headers[$race_name] = $result['individual_results_sets'][0]['results_headers'];
        $gender_finishers[$race_name] = 0;
        
        // Process division data
        foreach ($division_finishers[$race_name] as $did => $div_finishers) {
            $dpi = 'division-' . $did . '-placement';
            if ($result_data[$dpi]) {
                $division_placement_id[$race_name] = $dpi;
                $division_id[$race_name] = $did;
            }
            if ($gender[$race_name] && str_contains($results_headers[$race_name][$dpi], $gender[$race_name]) && 
                !str_contains($results_headers[$race_name][$dpi], 'Overall')) {
                $gender_finishers[$race_name] += $division_finishers[$race_name][$did];
            }
        }
        if(isset($division_placement_id[$race_name]) && isset($result_data[$division_placement_id[$race_name]])) {
            $division_place[$race_name] = $result_data[$division_placement_id[$race_name]];
        }
        $gender_place_id = array_search('Gender Place', $results_headers[$race_name]);
        $gender_place[$race_name] = $result_data[$gender_place_id] ?? '';
        
    }
}

// If searching by name, decide whether to select or prompt user
if ($searchingByName) {
    // Deduplicate by bib
    $uniqueByBib = [];
    foreach ($candidates as $cand) {
        if (!isset($uniqueByBib[$cand['bib']])) {
            $uniqueByBib[$cand['bib']] = $cand;
        }
    }
    $candidates = array_values($uniqueByBib);
    if (count($candidates) === 1) {
        // Auto-select the sole match
        $bib_num = $candidates[0]['bib'];
    } elseif (count($candidates) > 1) {
        // Render selection UI and exit early
        ?>
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Select Participant - <?php echo htmlspecialchars($race_display_name); ?></title>
            <link rel="stylesheet" href="assets/bootstrap/css/bootstrap.min.css">
            <style>
                .wrap { max-width: 960px; margin: 24px auto; background:#fff; border:1px solid #e0e0e0; border-radius:12px; box-shadow:0 8px 16px rgba(0,0,0,0.06); }
                .header { padding:16px 18px; display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid #eee; }
                .muted { color:#777; font-size:0.95em; }
                table { width:100%; border-collapse:collapse; }
                th, td { padding:12px 10px; border-bottom:1px solid #eee; font-size:0.95em; }
                tr:hover { background:#fafafa; }
                .actions { padding:12px 18px; display:flex; gap:10px; justify-content:flex-end; }
                .btn-primary-like { background:#ff8c00; color:#fff; border:none; border-radius:8px; padding:10px 14px; font-weight:600; }
                .btn-primary-like:hover { background:#e67e00; }
                .btn-secondary-like { background:#f0f0f0; color:#333; border:none; border-radius:8px; padding:10px 14px; font-weight:600; }
                .btn-secondary-like:hover { background:#e6e6e6; }
            </style>
        </head>
        <body>
            <div class="wrap">
                <div class="header">
                    <div>
                        <div style="font-weight:700; font-size:1.05em;">Select Participant</div>
                        <div class="muted">Matches for last name: <strong><?php echo htmlspecialchars($runner_name); ?></strong></div>
                    </div>
                    <div>
                        <button class="btn-secondary-like" onclick="history.back()">Back</button>
                    </div>
                </div>
                <form id="candidateForm" action="results.php" method="POST">
                    <table id="candidateTable" style="width:100%; border-collapse:collapse; margin-top:20px;">
                        <thead>
                            <tr style="background-color:#f0f0f0; border-bottom:2px solid #ddd;">
                                <th style="padding:12px; text-align:left;">Name</th>
                                <th style="padding:12px; text-align:left;">Bib</th>
                                <th style="padding:12px; text-align:left;">Event</th>
                                <th style="padding:12px; text-align:left;">Age/Gender</th>
                                <th style="padding:12px; text-align:left;">City, ST</th>
                            </tr>
                        </thead>
                        <tbody>
                        <?php 
                        $rowIndex = 0;
                        foreach ($candidates as $cand) { 
                            $rowIndex++;
                            $rowColor = ($rowIndex % 2 === 0) ? '#f9f9f9' : '#ffffff';
                            $hoverColor = '#e8f4f8';
                            $bib = htmlspecialchars($cand['bib']);
                        ?>
                            <tr style="cursor:pointer; background-color:<?php echo $rowColor; ?>; border-bottom:1px solid #eee;" 
                                data-bib="<?php echo $bib; ?>"
                                onmouseover="this.style.backgroundColor='<?php echo $hoverColor; ?>';"
                                onmouseout="this.style.backgroundColor='<?php echo $rowColor; ?>';">
                                <td style="padding:12px;"><?php echo htmlspecialchars(trim($cand['first_name'].' '.$cand['last_name'])); ?></td>
                                <td style="padding:12px;"><?php echo htmlspecialchars($cand['bib']); ?></td>
                                <td style="padding:12px;"><?php echo htmlspecialchars($cand['event']); ?></td>
                                <td style="padding:12px;"><?php echo htmlspecialchars(($cand['age'] ?: '-') . ' / ' . ($cand['gender'] ?: '-')); ?></td>
                                <td style="padding:12px;"><?php echo htmlspecialchars(trim(($cand['city'] ?: '').(($cand['state'] ?? '') ? ', '.$cand['state'] : ''))); ?></td>
                            </tr>
                        <?php } ?>
                        </tbody>
                    </table>
                    <div class="actions">
                        <input type="hidden" name="race_id" value="<?php echo htmlspecialchars($race_id); ?>">
                        <input type="hidden" name="timeout" value="<?php echo htmlspecialchars($timeout); ?>">
                        <input type="hidden" name="label_color" value="<?php echo htmlspecialchars($label_color); ?>">
                        <input type="hidden" name="data_color" value="<?php echo htmlspecialchars($data_color); ?>">
                        <input type="hidden" name="name_color" value="<?php echo htmlspecialchars($name_color); ?>">
                        <input type="hidden" name="search_type" value="<?php echo htmlspecialchars(isset($_SESSION['search_type']) ? $_SESSION['search_type'] : ($searchingByName ? 'name' : 'bib')); ?>">
                        <input type="hidden" name="runner_name" value="<?php echo htmlspecialchars($runner_name ?? ''); ?>">
                        <input type="hidden" name="bib_num" id="selectedBib">
                        <button type="button" class="btn-secondary-like" onclick="history.back()">Cancel</button>
                    </div>
                </form>
                <script>
                    console.log('Script loaded, looking for table...');
                    var table = document.getElementById('candidateTable');
                    console.log('Table found:', table);
                    var form = document.getElementById('candidateForm');
                    var input = document.getElementById('selectedBib');
                    console.log('Form found:', form, 'Input found:', input);
                    
                    if (table && form && input) {
                        console.log('Adding click listener to table');
                        table.addEventListener('click', function(e) {
                            console.log('Table clicked!', e.target);
                            
                            // Don't handle clicks on buttons or headers
                            if (e.target.tagName === 'BUTTON' || e.target.tagName === 'TH') {
                                console.log('Click on button or header, ignoring');
                                return;
                            }
                            
                            // Find the parent TR element by walking up the DOM
                            var target = e.target;
                            var tr = null;
                            while (target && target !== table) {
                                if (target.tagName === 'TR') {
                                    tr = target;
                                    console.log('Found TR:', tr);
                                    break;
                                }
                                target = target.parentElement;
                            }
                            
                            // Check if this row has a bib number (skip header rows)
                            if (tr) {
                                var bib = tr.getAttribute('data-bib');
                                console.log('TR has data-bib:', bib);
                                if (bib) {
                                    console.log('Setting bib value:', bib);
                                    // Set the bib number
                                    input.value = bib;
                                    
                                    // Clear runner_name for this submission, but DON'T change search_type
                                    // We want to keep the original search_type='name' in session for redirect
                                    var runnerNameInput = form.querySelector('input[name="runner_name"]');
                                    if (runnerNameInput) {
                                        runnerNameInput.value = '';
                                        console.log('Cleared runner_name for this submission');
                                    }
                                    // Don't change search_type - keep it as 'name' so redirect goes back to name search
                                    
                                    console.log('Submitting form with bib:', bib);
                                    form.submit();
                                } else {
                                    console.log('No data-bib attribute found');
                                }
                            } else {
                                console.log('No TR found');
                            }
                        });
                        console.log('Click listener added successfully');
                    } else {
                        console.error('Missing elements:', {table: !!table, form: !!form, input: !!input});
                    }
                </script>
            </div>
        </body>
        </html>
        <?php
        exit;
    }
}

// Age group mapping for display
$age_groups = [
    "M Overall" => "Male Overall",
    "F Overall" => "Female Overall", 
    "X Overall" => "Non-Binary Overall",
    "F0114" => "Female 14 & Under",
    "F1519" => "Female 15 - 19",
    "F0119" => "Female 19 & Under",
    "F2024" => "Female 20 - 24",
    "F2529" => "Female 25 - 29",
    "F3034" => "Female 30 - 34",
    "F3539" => "Female 35 - 39",
    "F4044" => "Female 40 - 44",
    "F4549" => "Female 45 - 49",
    "F5054" => "Female 50 - 54",
    "F5559" => "Female 55 - 59",
    "F6064" => "Female 60 - 64",
    "F6569" => "Female 65 - 69",
    "F2029" => "Female 20 - 29",
    "F3039" => "Female 30 - 39",
    "F4049" => "Female 40 - 49",
    "F5059" => "Female 50 - 59",
    "F6069" => "Female 60 - 69",
    "F70F9" => "Female 70 - 79",
    "F8089" => "Female 80 - 89",
    "F7099" => "Female 70 & Over",
    "F7599" => "Female 75 & Over",
    "F8099" => "Female 80 & Over",
    "F8599" => "Female 85 & Over",
    "F9099" => "Female 90 & Over",
    "M0114" => "Male 14 & Under",
    "M1519" => "Male 15 - 19",
    "M0119" => "Male 19 & Under",
    "M2024" => "Male 20 - 24",
    "M2529" => "Male 25 - 29",
    "M3034" => "Male 30 - 34",
    "M3539" => "Male 35 - 39",
    "M4044" => "Male 40 - 44",
    "M4549" => "Male 45 - 49",
    "M5054" => "Male 50 - 54",
    "M5559" => "Male 55 - 59",
    "M6064" => "Male 60 - 64",
    "M6569" => "Male 65 - 69",
    "M2029" => "Male 20 - 29",
    "M3039" => "Male 30 - 39",
    "M4049" => "Male 40 - 49",
    "M5059" => "Male 50 - 59",
    "M6069" => "Male 60 - 69",
    "M7079" => "Male 70 - 79",
    "M8089" => "Male 80 - 89",
    "M7599" => "Male 75 & Over",
    "M8099" => "Male 80 & Over",
    "M8599" => "Male 85 & Over",
    "M9099" => "Male 90 & Over",
    "M7099" => "Male 70 & Over"
];

?>
<!DOCTYPE html>
<html data-bs-theme="light" lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="canonical" href="<?php echo htmlspecialchars($share_url); ?>">
    <meta property="og:title" content="<?php echo htmlspecialchars($og_title); ?>">
    <meta property="og:description" content="<?php echo htmlspecialchars($og_desc); ?>">
    <meta property="og:type" content="website">
    <meta property="og:url" content="<?php echo htmlspecialchars($share_url); ?>">
    <meta property="og:image" content="<?php echo htmlspecialchars($og_image); ?>">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="<?php echo htmlspecialchars($og_title); ?>">
    <meta name="twitter:description" content="<?php echo htmlspecialchars($og_desc); ?>">
    <meta name="twitter:image" content="<?php echo htmlspecialchars($og_image); ?>">
    <meta http-equiv="refresh" content="<?php echo $timeout; ?>;URL='bibsearch.php?race_id=<?php 
        // Use current POST value if available, otherwise check session
        $current_search_type = isset($_POST['search_type']) ? $_POST['search_type'] : (isset($_SESSION['search_type']) ? $_SESSION['search_type'] : 'bib');
        $current_runner_name = isset($_POST['runner_name']) && $_POST['runner_name'] !== '' ? $_POST['runner_name'] : (isset($_SESSION['runner_name']) && $_SESSION['runner_name'] !== '' ? $_SESSION['runner_name'] : '');
        $current_bib_num = isset($_POST['bib_num']) && $_POST['bib_num'] !== '' ? $_POST['bib_num'] : (isset($_SESSION['bib_num']) && $_SESSION['bib_num'] !== '' ? $_SESSION['bib_num'] : '');
        
        // Fallback: if search_type is not 'name' but we have runner_name, assume it was a name search
        if ($current_search_type !== 'name' && $current_runner_name !== '') {
            $current_search_type = 'name';
        }
        
        if ($current_search_type === 'name' && $current_runner_name !== '') {
            echo urlencode($race_id) . '&timeout=' . urlencode($timeout) . '&search_type=name&runner_name=' . urlencode($current_runner_name);
        } else {
            echo urlencode($race_id) . '&timeout=' . urlencode($timeout) . '&search_type=bib&bib_num=' . urlencode($current_bib_num);
        }
    ?>'">
    <title>Race Results - Bay City Timing & Events</title>
    <link rel="stylesheet" href="assets/bootstrap/css/bootstrap.min.css">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Aleo&amp;display=swap">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Alfa+Slab+One&amp;display=swap">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Anek+Tamil&amp;display=swap">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Rubik+Dirt&amp;display=swap">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Rubik+Distressed&amp;display=swap">
    <link rel="stylesheet" href="assets/style/styles.css">
    <style>
        /* No Results Modal (fallback styles to ensure it looks good) */
        .modal-overlay {
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.65);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 9999;
            visibility: visible;
            opacity: 1;
        }
        .modal-overlay.hidden { display: none; }
        .modal-content {
            width: min(520px, 92vw);
            background: #ffffff;
            border-radius: 14px;
            box-shadow: 0 18px 60px rgba(0,0,0,0.25);
            padding: 28px 24px;
            text-align: center;
            animation: popin 200ms ease-out;
        }
        @keyframes popin { from { transform: scale(0.97); opacity: 0.8; } to { transform: scale(1); opacity: 1; } }
        .no-results-icon {
            width: 72px;
            height: 72px;
            margin: 0 auto 14px;
            border-radius: 50%;
            background: #ffe9e9;
            display: grid;
            place-items: center;
            color: #cc0000;
            font-size: 36px;
            font-weight: bold;
        }
        .no-results-title {
            font-family: 'Alfa Slab One';
            font-size: 28px;
            margin: 6px 0 8px;
        }
        .no-results-text {
            font-family: Arial, Helvetica, sans-serif;
            font-size: 16px;
            color: #555;
            line-height: 1.45;
            margin: 0 0 18px;
        }
        .modal-actions {
            display: flex;
            gap: 12px;
            justify-content: center;
            flex-wrap: wrap;
        }
        .btn-primary-like, .btn-secondary-like, .btn-fb-like, .btn-link-like {
            border: none;
            border-radius: 8px;
            padding: 12px 16px;
            cursor: pointer;
            font-weight: 600;
            letter-spacing: 0.2px;
        }
        .btn-primary-like { background: #ff8c00; color: #fff; }
        .btn-primary-like:hover { background: #e67e00; }
        .btn-secondary-like { background: #f0f0f0; color: #333; }
        .btn-secondary-like:hover { background: #e6e6e6; }
        .btn-fb-like { background:#1877F2; color:#fff; }
        .btn-fb-like:hover { background:#155fbe; }
        .btn-link-like { background:#6c757d; color:#fff; }
        .btn-link-like:hover { background:#5a6268; }
        .share-buttons-container {
            display: none;
        }
        @media (max-width: 767px) {
            .share-buttons-container {
                display: flex;
            }
        }

        /* Body styling */
        .results-body {
            background-size: cover;
            background-position: center center;
            background-repeat: no-repeat;
            background-attachment: fixed;
            height: 100vh;
            margin: 0;
        }
        
        /* Main content container */
        .main-content {
            max-width: fit-content;
            margin-left: auto;
            margin-right: auto;
        }
        
        /* Race logo responsive styling */
        .race-logo {
            max-width: 300px;
            max-height: 150px;
            width: auto;
            height: auto;
            border-radius: 8px;
            transition: transform 0.3s ease;
        }
        
        .race-logo:hover {
            transform: scale(1.05);
        }
        
        /* Result display styling */
        .result-container {
            margin-left: 300px;
            display: none;
        }
        
        .result-name {
            font-family: 'Alfa Slab One';
            font-size: 50px;
            display: inline-block;
            line-height: 1;
            -webkit-text-stroke-width: 2px;
            -webkit-text-stroke-color: white;
            color: <?php echo htmlspecialchars($name_color); ?>;
        }
        
        .result-time {
            font-family: 'Rubik Distressed';
            font-size: 100px;
            display: inline-block;
            line-height: 1;
            color: <?php echo htmlspecialchars($data_color); ?>;
        }
        
        .result-label {
            font-family: 'Alfa Slab One';
            font-size: 30px;
            color: <?php echo htmlspecialchars($label_color); ?>;
            display: inline-block;
            line-height: 1;
        }
        
        .result-value {
            font-family: 'Rubik Distressed';
            font-size: 20px;
            display: inline-block;
            line-height: 1;
            color: <?php echo htmlspecialchars($data_color); ?>;
        }
        
        .finisher-label {
            font-family: 'Rubik Distressed';
            font-size: 30px;
            color: <?php echo htmlspecialchars($data_color); ?>;
            display: inline-block;
            line-height: 1;
        }
        
        /* Responsive logo sizing */
        @media (max-width: 768px) {
            .race-logo {
                max-width: 250px;
                max-height: 120px;
            }
            .result-container {
                margin-left: 50px;
            }
        }
        
        @media (max-width: 480px) {
            .race-logo {
                max-width: 200px;
                max-height: 100px;
            }
            .result-container {
                margin-left: 20px;
            }
            .result-name {
                font-size: 40px;
            }
            .result-time {
                font-size: 80px;
            }
        }
        
        @media (max-width: 320px) {
            .race-logo {
                max-width: 150px;
                max-height: 75px;
            }
            .result-container {
                margin-left: 10px;
            }
            .result-name {
                font-size: 30px;
            }
            .result-time {
                font-size: 60px;
            }
        }
    </style>
</head>
<body class="results-body"<?php if (!empty($background_color)) { echo ' style="background-color: ' . htmlspecialchars($background_color) . '"'; } ?>>
<div id="main_content" class="container main-content">
    <?php if (!empty($logo_url) || !empty($sponsor_logo)): ?>
    <div class="row text-center" style="margin-top: 20px; margin-bottom: 30px;">
        <div class="col-md-12" style="display:flex; gap:16px; align-items:center; justify-content:center;">
            <?php if (!empty($logo_url)) { ?>
            <img src="<?php echo htmlspecialchars($logo_url); ?>" alt="Race Logo" class="race-logo">
            <?php } ?>
            <?php if (!empty($sponsor_logo)) { ?>
            <img src="<?php echo htmlspecialchars($sponsor_logo); ?>" alt="Sponsor Logo" class="race-logo" style="max-height:100px;">
            <?php } ?>
        </div>
    </div>
    <?php endif; ?>
</div>
<?php 
    if (empty($race_names)) {
?>
<div id="noResultsModal" class="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="noResultsTitle">
    <div class="modal-content">
        <?php if (!empty($logo_url)) { ?>
        <div style="margin-bottom:12px;">
            <img src="<?php echo htmlspecialchars($logo_url); ?>" alt="Race Logo" class="race-logo" style="max-height:80px;">
        </div>
        <?php } ?>
        <div class="no-results-icon">!</div>
        <div id="noResultsTitle" class="no-results-title">No Results Found</div>
        <p class="no-results-text">We couldn’t find results for bib <strong><?php echo htmlspecialchars($bib_num ?? ''); ?></strong> for this event. Please verify the bib number or try a different search.</p>
        <div class="modal-actions">
            <button id="backToSearchBtn" class="btn-primary-like" onclick="hideModal()">Back to Search</button>
            <button class="btn-secondary-like" onclick="window.location.href='bibsearch.php?race_id=<?php echo urlencode($race_id) . '&timeout=' . urlencode($timeout); ?>'">Change Bib/Name</button>
        </div>
    </div>
</div>
<?php 
    } else {
    foreach ($race_names as $race_name => $race_name_id) { ?>
    <div id="<?php echo $race_name_id ?>" class="container result-container">
        <?php if (!empty($logo_url) || !empty($sponsor_logo)): ?>
        <div class="row text-center" style="margin-top: 20px; margin-bottom: 20px;">
            <div class="col-md-12" style="display:flex; gap:16px; align-items:center; justify-content:center;">
                <?php if (!empty($logo_url)) { ?>
                <img src="<?php echo htmlspecialchars($logo_url); ?>" alt="Race Logo" class="race-logo">
                <?php } ?>
                <?php if (!empty($sponsor_logo)) { ?>
                <img src="<?php echo htmlspecialchars($sponsor_logo); ?>" alt="Sponsor Logo" class="race-logo" style="max-height:100px;">
                <?php } ?>
            </div>
        </div>
        <?php endif; ?>
        
        <div class="row text-center">
            <div class="col-md-12" style="margin-top: 50px;">
                <span class="result-name"><?php echo $first_name[$race_name] . " " . $last_name[$race_name] ?></span>
            </div>
        </div>
        
        
        <div class="row text-center">
            <div class="col-md-12">
                <span class="result-time"><?php echo $chip_time[$race_name] ?></span>
            </div>
        </div>
        
        <div class="row">
            <div class="col-md-12 text-center" style="margin-top: 25px;">
                <span class="finisher-label fw-bold"><?php echo $race_name; ?> FINISHER</span>
            </div>
        </div>
        
        <div class="row">
            <div class="col-md-12 text-center" style="margin-top: 25px;">
                <span class="result-label fw-bold">BIB NUMBER</span>
            </div>
        </div>
        <div class="row">
            <div class="col">
                <div class="row text-center">
                    <div class="col-md-12">
                        <span class="result-value"><?php echo $bib_num; ?></span>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="row">
            <div class="col-md-12 text-center" style="margin-top: 25px;">
                <span class="result-label fw-bold">OVERALL RANK</span>
            </div>
        </div>
        <div class="row">
            <div class="col">
                <div class="row text-center">
                    <div class="col-md-12">
                        <span class="result-value"><?php echo $place[$race_name]; ?> of <?php echo $finishers[$race_name]; ?></span>
                    </div>
                </div>
            </div>
        </div>
        
        <?php if (!empty($gender[$race_name])): ?>
        <div class="row">
            <div class="col-md-12 text-center" style="margin-top: 25px;">
                <span class="result-label fw-bold">GENDER RANK</span>
            </div>
        </div>
        <div class="row">
            <div class="col">
                <div class="row text-center">
                    <div class="col-md-12">
                        <span class="result-value"><?php echo $gender_place[$race_name]; ?> of <?php echo $gender_finishers[$race_name]; ?></span>
                    </div>
                </div>
            </div>
        </div>
        <?php endif; ?>
        
        <?php if (isset($division_placement_id[$race_name]) && isset($results_headers[$race_name][$division_placement_id[$race_name]])): ?>
        <div class="row">
            <div class="col-md-12 text-center" style="margin-top: 25px;">
                <span class="result-label fw-bold">
                    <?php 
                    $agheader = array_key_exists($results_headers[$race_name][$division_placement_id[$race_name]], $age_groups)
                        ? $age_groups[$results_headers[$race_name][$division_placement_id[$race_name]]] 
                        : $results_headers[$race_name][$division_placement_id[$race_name]];
                    echo $agheader;
                    ?>
                </span>
            </div>
        </div>
        <div class="row">
            <div class="col">
                <div class="row text-center">
                    <div class="col-md-12">
                        <span class="result-value"><?php 
                        if(isset($division_place[$race_name])) {
                            echo $division_place[$race_name];
                        } else {
                            echo '0';
                        }
                        ?> of <?php 
                        if(isset($division_id[$race_name]) && isset($division_finishers[$race_name][$division_id[$race_name]])) {
                            echo $division_finishers[$race_name][$division_id[$race_name]];
                        } else {
                            echo '0';
                        }
                        ?></span>  
                    </div>
                </div>
            </div>
        </div>
        <?php endif; ?>
        
        <div class="row">
            <div class="col-md-12 text-center" style="margin-top: 25px;">
                <span class="result-label fw-bold">AVERAGE PACE</span>
            </div>
        </div>
        <div class="row">
            <div class="col">
                <div class="row text-center">
                    <div class="col-md-12">
                        <span class="result-value"><?php echo $pace[$race_name] ?></span>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Share actions (below results, above any bottom elements) - Mobile only -->
        <div class="row text-center share-buttons-container" style="margin-top: 24px; margin-bottom: 16px;">
            <div class="col-md-12" style="display:flex; gap:12px; align-items:center; justify-content:center; flex-wrap:wrap;">
                <button type="button" class="btn-primary-like" onclick="shareNative()">Share</button>
                <button type="button" class="btn-fb-like" onclick="shareFacebook()">Facebook</button>
                <button type="button" class="btn-link-like" onclick="copyShareLink()">Copy Link</button>
            </div>
        </div>
    </div>
    <?php
    }
    if (count($race_names) > 1) {
        echo '<div class="race-selector text-center" style="margin-top: 20px;">';
        foreach ($race_names as $race_name => $race_name_id) {
            echo '<button type="button" class="btn btn-primary me-2" onclick="switchRace(\'' . $race_name_id . '\')">' . 
                 htmlspecialchars($race_name) . '</button>';
        }
        echo '</div>';
    } else { 
        $race_name_id = $race_names[array_key_first($race_names)];
    ?>
    
    <script>
        document.getElementById("main_content").innerHTML = document.getElementById('<?php echo $race_name_id;?>').innerHTML;
        openFullscreen();
    </script>
    <?php
    }
    }
    ?>
    <script src="assets/bootstrap/js/bootstrap.min.js"></script>
    <script>
        const elem = document.documentElement;
        const SHARE_URL = <?php echo json_encode($share_url); ?>;
        const SHARE_TITLE = <?php echo json_encode($og_title); ?>;
        const SHARE_TEXT = <?php echo json_encode($og_desc); ?>;
        
        /**
         * Switch to a different race result
         */
        function switchRace(raceId) {
            const raceElement = document.getElementById(raceId);
            if (raceElement) {
                document.getElementById("main_content").innerHTML = raceElement.innerHTML;
                openFullscreen();
            }
        }
        
        /**
         * Open fullscreen mode
         */
        function openFullscreen() {
            if (elem.requestFullscreen) {
                elem.requestFullscreen();
            } else if (elem.webkitRequestFullscreen) { /* Safari */
                elem.webkitRequestFullscreen();
            } else if (elem.msRequestFullscreen) { /* IE11 */
                elem.msRequestFullscreen();
            }
        }

        // Sharing helpers
        function shareFacebook() {
            const u = encodeURIComponent(SHARE_URL);
            const fb = `https://www.facebook.com/sharer/sharer.php?u=${u}`;
            window.open(fb, '_blank', 'noopener,noreferrer,width=680,height=500');
        }
        function copyShareLink() {
            try {
                navigator.clipboard.writeText(SHARE_URL).then(() => {
                    alert('Link copied to clipboard');
                }).catch(() => {
                    // Fallback
                    const ta = document.createElement('textarea');
                    ta.value = SHARE_URL;
                    document.body.appendChild(ta);
                    ta.select();
                    document.execCommand('copy');
                    document.body.removeChild(ta);
                    alert('Link copied to clipboard');
                });
            } catch (e) {
                window.prompt('Copy this link:', SHARE_URL);
            }
        }
        function shareNative() {
            if (navigator.share) {
                navigator.share({ title: SHARE_TITLE, text: SHARE_TEXT, url: SHARE_URL }).catch(() => {});
            } else {
                // Fallback to Facebook share if Web Share not supported
                shareFacebook();
            }
        }
        
        /**
         * Shows the 'No Results Found' modal pop-up
         */
        function showModal() {
            const modal = document.getElementById('noResultsModal');
            if (modal) {
                modal.classList.add('visible');
            }
        }
        
        /**
         * Returns the URL to redirect to search page, preserving search type
         */
        function getSearchRedirectUrl() {
            <?php
            $current_search_type_js = isset($_SESSION['search_type']) ? $_SESSION['search_type'] : 'bib';
            $current_runner_name_js = isset($_SESSION['runner_name']) && $_SESSION['runner_name'] !== '' ? $_SESSION['runner_name'] : '';
            $current_bib_num_js = isset($_SESSION['bib_num']) && $_SESSION['bib_num'] !== '' ? $_SESSION['bib_num'] : '';
            
            // Fallback: if search_type is not 'name' but we have runner_name, assume it was a name search
            if ($current_search_type_js !== 'name' && $current_runner_name_js !== '') {
                $current_search_type_js = 'name';
            }
            
            if ($current_search_type_js === 'name' && $current_runner_name_js !== '') {
                $redirect_url = urlencode($race_id) . '&timeout=' . urlencode($timeout) . '&search_type=name&runner_name=' . urlencode($current_runner_name_js);
            } else {
                $redirect_url = urlencode($race_id) . '&timeout=' . urlencode($timeout) . '&search_type=bib&bib_num=' . urlencode($current_bib_num_js);
            }
            ?>
            return "bibsearch.php?race_id=<?php echo $redirect_url; ?>";
        }
        
        /**
         * Hides the 'No Results Found' modal pop-up
         */
        function hideModal() {
            window.location.href = getSearchRedirectUrl();
        }
        
        // Hide the modal when the user clicks the dark background
        document.addEventListener('DOMContentLoaded', function() {
            const modal = document.getElementById('noResultsModal');
            if (modal) {
                // Focus the "Back to Search" button so user can press Enter
                const backBtn = document.getElementById('backToSearchBtn');
                if (backBtn) {
                    // Use setTimeout to ensure the modal is fully rendered
                    setTimeout(function() {
                        backBtn.focus();
                    }, 100);
                }
                
                // Set 20 second timeout to automatically return to search
                setTimeout(function() {
                    hideModal();
                }, 20000);
                
                // Handle Escape key to close modal
                document.addEventListener('keydown', function(e) {
                    if (e.key === 'Escape' && modal) {
                        hideModal();
                    }
                });
                
                modal.addEventListener('click', function(e) {
                    if (e.target.id === 'noResultsModal') {
                        hideModal();
                    }
                });
            }
            
            // Add click handler to runner name only to return to search
            const runnerNames = document.querySelectorAll('.result-name');
            runnerNames.forEach(function(runnerName) {
                runnerName.style.cursor = 'pointer';
                runnerName.title = 'Click to return to search';
                runnerName.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    window.location.href = getSearchRedirectUrl();
                });
            });
        });
    </script>

<script>
// Open Settings: Win/Linux Ctrl+Alt+S, macOS Option+Command+S
(function(){
  var lastTs = 0;
  function handler(e){
    // Ignore when typing in inputs/textareas or contentEditable
    var t = e.target;
    if (t && ((t.tagName === 'INPUT') || (t.tagName === 'TEXTAREA') || t.isContentEditable)) return;
    var isMacCombo = e.metaKey && e.altKey && (e.code === 'KeyS');
    var isWinCombo = e.ctrlKey && e.altKey && (e.code === 'KeyS');
    if (!(isMacCombo || isWinCombo)) return;
    var now = Date.now();
    if (now - lastTs < 500 || e.repeat) return; // debounce and ignore held key
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
