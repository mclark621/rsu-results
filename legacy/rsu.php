<?php
require('ApiConfig.php');
session_start();

// --- Placeholder for Token Storage ---
// In a production app, you would verify if a valid, non-expired token exists here.
$access_token = isset($_SESSION['rsu_access_token']) ? $_SESSION['rsu_access_token'] : null;

// --- OAuth2 Flow Initiation ---
if (!$access_token && !isset($_GET['code'])) {
    
    // Step 1: Initiate the Authorization Request

    // Generate a unique state token to prevent CSRF attacks
    $_SESSION['oauth2_state'] = bin2hex(random_bytes(16));
    strtr(rtrim(base64_encode(hash('sha256', $codeVerifier, true)), '='), '+/', '-_');
    $_SESSION['code_verifier'] = $codeVerifier;
    $auth_params = [
        'client_id'     => RSU_CLIENT_ID,
        'redirect_uri'  => RSU_REDIRECT_URI,
        'code_challenge_method' => 'S256',
        'code_challenge' => $codeVerifier,
        'response_type' => 'code', // Standard flow for server-side apps
        'state'         => $_SESSION['oauth2_state']
    ];
    
    $auth_url = RSU_AUTH_ENDPOINT . '?' . http_build_query($auth_params);
    
    // Redirect the user to the RunSignup login/authorization page
    header('Location: ' . $auth_url);
    exit;
}

?>
