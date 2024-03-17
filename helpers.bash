# mpv
function mpvdvd () {
	mpv dvd:// --dvd-device=$1 --screenshot-template="$(dirname $1)/screenshot/screenshot-%F-time-%wH-%wM-%wS-%wT" "${@:2}" ;
}

function mpvbd () {
	mpv bd:// --bluray-device=$1 --screenshot-template="$(dirname $1)/screenshot/screenshot-%F-time-%wH-%wM-%wS-%wT" "${@:2}" ;
}


