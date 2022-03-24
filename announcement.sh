
echo "================================="
echo $2
echo $3
echo "================================="


curl -X POST $1 -d "content=:smile: @everyone :smile:
New post! Check it out here: [$2]($3)"
