

echo $WEBHOOK
echo $LINK
echo $TITLE

# curl -X POST "${{secrets.DISCORD_ANNOUNCEMENT_WEBHOOK}}" -d "content=:pepefrog: @everyone :pepefrog:\nNew post! Check it out here: [${{github.events.input.postLink}}](${{github.events.input.postTitle}})"
