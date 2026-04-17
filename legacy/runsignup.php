<?php

// NOTE: Bib numbers should have been set up for this event already from
// 1 to RESULTS_TEST1_NUM_PARTICIPANTS

// NOTE: Copy ApiConfig.sample.php to ApiConfig.php and modify
// Get up some config
require('ApiConfig.php');

require('RunSignupRestClient.class.php');

// Check if there are timer settings
$loggedIn = false;
if (defined('TIMER_API_KEY') && TIMER_API_KEY && defined('TIMER_API_SECRET') && TIMER_API_SECRET)
{
    echo "keys";
	// Set up API
	$restClient = new RunSignupRestClient(ENDPOINT, PROTOCOL, TIMER_API_KEY, TIMER_API_SECRET);
}
else
{
	$loggedIn = true;
	// Get password
	if (defined('API_LOGIN_PASSWORD') && API_LOGIN_PASSWORD)
		$password = API_LOGIN_PASSWORD;
	else
	{
		echo "Password: ";
		system('stty -echo');
		$password = trim(fgets(STDIN));
		system('stty echo');
		// Add a new line since the user's newline didn't echo
		echo "\n";
	}
	
	// Login to API
	$restClient = new RunSignupRestClient(ENDPOINT, PROTOCOL, null, null);
	if (!$restClient->login(API_LOGIN_EMAIL, $password))
		die("Failed to login.\n");
}

// Set response format
$restClient->setReturnFormat('json');
// Set up URL prefix
$urlPrefix = 'Race/' . RESULTS_TEST1_RACE_ID . '/results/get-results?event_id=767114&bib_num=1640';
// Get race information
$resp = $restClient->callMethod($urlPrefix, 'GET', null, null, true);
print("<pre>".print_r($resp['individual_results_sets'][0],true)."</pre>");
if (!$resp)
	die("Request failed.\n".$restClient->lastRawResponse);
if (isset($resp['error']))
	die(print_r($resp,1) . PHP_EOL);
// Get event info
$event = null;
foreach ($resp['race']['events'] as $tmp)
echo var_dump($tmp) . "<br>";
		$event = $tmp;
if (!$event)
	die("Event not found.\n");


// Logout
if ($loggedIn)
	$restClient->logout();

?>
