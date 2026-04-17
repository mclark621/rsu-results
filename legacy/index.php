<?php
require('ApiConfig.php');
session_start();

// If race_id is provided, immediately redirect to bibsearch.php without OAuth
if (isset($_GET['race_id']) && !empty($_GET['race_id'])) {
    $race_id = $_GET['race_id'];
    header('Location: bibsearch.php?race_id=' . urlencode($race_id));
    exit;
}

// --- Placeholder for Token Storage ---
// In a production app, you would verify if a valid, non-expired token exists here.
$access_token = isset($_SESSION['rsu_access_token']) ? $_SESSION['rsu_access_token'] : null;

// --- OAuth2 Flow Initiation ---
if (!$access_token && !isset($_GET['code'])) {
    // Step 1: Initiate the Authorization Request
    
    // Generate a unique state token to prevent CSRF attacks
    $_SESSION['oauth2_state'] = bin2hex(random_bytes(16));
    
    // Generate code verifier and challenge for PKCE
    $codeVerifier = bin2hex(random_bytes(32));
    $codeChallenge = strtr(rtrim(base64_encode(hash('sha256', $codeVerifier, true)), '='), '+/', '-_');
    $_SESSION['code_verifier'] = $codeVerifier;
    
    $auth_params = [
        'client_id'          => RSU_CLIENT_ID,
        'redirect_uri'       => RSU_REDIRECT_URI,
        'code_challenge_method' => 'S256',
        'code_challenge'     => $codeChallenge,
        'response_type'      => 'code', // Standard flow for server-side apps
        'scope'              => RSU_SCOPE,
        'state'              => $_SESSION['oauth2_state']
    ];
    
    $auth_url = RSU_AUTH_ENDPOINT . '?' . http_build_query($auth_params);
    
    // Redirect the user to the RunSignup login/authorization page
    header('Location: ' . $auth_url);
    exit;
}

// --- HTML Document ---
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Bay City Timing & Events</title>
    <link rel="stylesheet" href="assets/style/stylesheets.css">
</head>
<body>
    <div class="form-container">
        <div class="logo">
            <img src="assets/img/bctlogo.png" alt="Bay City Timing & Events Logo">
        </div>
        <form class="stylish-form" action="selfie.php" method="POST">
            <?php
            // Set default dates to today
            $start_date = date("Y-m-d");
            $end_date = date("Y-m-d");
            
            // Use POST data if available
            if (isset($_POST['start_date'])) {
                $start_date = $_POST['start_date'];
            }
            if (isset($_POST['end_date'])) {
                $end_date = $_POST['end_date'];
            }
            ?>
            <label for="start_date_input">Start Date</label>
            <input type="date" name="start_date" id="start_date_input" value="<?php echo htmlspecialchars($start_date); ?>">
            
            <label for="end_date_input">End Date</label>
            <input type="date" name="end_date" id="end_date_input" value="<?php echo htmlspecialchars($end_date); ?>">
            
            <input type="submit" value="Submit Dates">
        </form>
    </div>
</body>
</html>