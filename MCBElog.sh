#!/usr/bin/env bash

syntax='Usage: MCBElog.sh SERVICE'

send() {
	if systemctl is-active --quiet "mcbe-bot@$instance"; then
		join=$(grep '^JOIN ' "$join_file")
		chans=$(echo "$join" | cut -d ' ' -f 2 -s)
		# Trim off $chans after first ,
		chan=${chans%%,*}
		echo "PRIVMSG $chan :$*" >> "$buffer"
	fi
	if [ -f "$webhook_file" ]; then
		# Escape \ while reading line from file
		while read -r url; do
			if echo "$url" | grep -Eq 'https://discord(app)?\.com'; then
				curl -X POST -H 'Content-Type: application/json' -d "{\"content\":\"$*\"}" "$url" &
			# Rocket Chat can be hosted by any domain
			elif echo "$url" | grep -q 'https://rocket\.'; then
				curl -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$*\"}" "$url" &
			fi
		done < "$webhook_file"
	fi
	wait
}

case $1 in
--help|-h)
	echo "$syntax"
	echo 'Post Minecraft Bedrock Edition server logs running in service to IRC and webhooks (Discord and Rocket Chat).'
	echo
	echo Logs include server start/stop and player connect/disconnect/kicks.
	exit
	;;
esac
if [ "$#" -lt 1 ]; then
	>&2 echo Not enough arguments
	>&2 echo "$syntax"
	exit 1
elif [ "$#" -gt 1 ]; then
	>&2 echo Too much arguments
	>&2 echo "$syntax"
	exit 1
fi

service=$1
if ! systemctl is-active --quiet "$service"; then
	>&2 echo "Service $service not active"
	exit 1
fi

# Trim off $service before last @
instance=${service##*@}
buffer=~mc/.MCBE_Bot/${instance}_BotBuffer
join_file=~mc/.MCBE_Bot/${instance}_BotJoin.txt
webhook_file=~mc/.MCBE_Bot/${instance}_BotWebhook.txt
chmod -f 600 "$webhook_file"

send "Server $instance starting"
trap 'send "Server $instance stopping"; pkill -s $$' EXIT
# Follow log for unit $service 0 lines from bottom, no metadata
journalctl -fu "$service" -n 0 -o cat | while read -r line; do
	if echo "$line" | grep -q 'Player connected'; then
		# Gamertags can have spaces as long as they're not leading/trailing/contiguous
		player=$(echo "$line" | cut -d ' ' -f 6- -s | cut -d , -f 1)
		send "$player connected to $instance"
	elif echo "$line" | grep -q 'Player disconnected'; then
		player=$(echo "$line" | cut -d ' ' -f 6- -s | cut -d , -f 1)
		send "$player disconnected from $instance"
	elif echo "$line" | grep -q Kicked; then
		player=$(echo "$line" | cut -d ' ' -f 2- -s | sed 's/ from the game:.*//')
		reason=$(echo "$line" | cut -d "'" -f 2- -s)
		# Trim off trailing ' from $reason
		reason=${reason%"'"}
		# Trim off leading space from $reason
		reason=${reason#' '}
		send "$player was kicked from $instance because $reason"
	fi
done
