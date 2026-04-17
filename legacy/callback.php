<?php
session_start();
// Load the configuration constants from your main file or config file
require('ApiConfig.php'); // Assuming your constants are here

// Check for the authorization code
if (!isset($_GET['code'])) {
    die("Authorization code not found. Login failed.");
}

// 1. Verify the state parameter to prevent CSRF
if ($_GET['state'] != $_SESSION['oauth2_state']) {
    die("Bad state parameter. Possible CSRF attack.");
}
// 2. Exchange the authorization code for an Access Token
$code = $_GET['code'];

$token_params = [
    'grant_type'    => 'authorization_code',
    'client_id'     => RSU_CLIENT_ID,
    'client_secret' => RSU_CLIENT_SECRET,
    'redirect_uri'  => RSU_REDIRECT_URI,
    'code_verifier' => $_SESSION['code_verifier'],
    'code'          => $code
];

// Perform the POST request to the token endpoint
$ch = curl_init(RSU_TOKEN_ENDPOINT);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($token_params));
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/x-www-form-urlencoded']);

$response = curl_exec($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($http_code !== 200) {
    die("Token exchange failed. HTTP Code: " . $http_code . " Response: " . $response);
}

// 3. Process the response and store the token
$token_data = json_decode($response, true);

if (isset($token_data['access_token'])) {
    // SUCCESS: Store the token and redirect to the main application page
    $_SESSION['rsu_access_token'] = $token_data['access_token'];
    
    // Optional: Store the token expiration and refresh token for later use
   $_SESSION['rsu_token_expires'] = time() + $token_data['expires_in'];
   $_SESSION['rsu_refresh_token'] = $token_data['refresh_token'];

    // Redirect to the main application page after successful login
    header('Location: index.php'); 
    exit;

} else {
    die("Failed to retrieve access token.");
}
?>
} else {
    die("Failed to retrieve access token.");
}
?>