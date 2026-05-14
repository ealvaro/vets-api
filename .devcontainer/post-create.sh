#!/bin/sh

# this runs at Codespace creation - not part of pre-build

echo "post-create start"
echo "$(date)    post-create start" >> "$HOME/status"

# Configure GHE authentication for git and bundler
if [ -n "$GHE_TOKEN" ]; then
  git config --global url."https://x-access-token:${GHE_TOKEN}@va.ghe.com/".insteadOf "https://va.ghe.com/"
  export BUNDLE_VA__GHE__COM="x-access-token:${GHE_TOKEN}"
fi

# update the repos
git -C /workspaces/vets-api-mockdata pull
git -C /workspaces/vets-api pull

mkdir -p /workspaces/vets-api/.vscode
cat > /workspaces/vets-api/.vscode/settings.json <<'EOF'
{
  "rubyLsp.rubyVersionManager": { "identifier": "rbenv" }
}
EOF

bundle install

echo "post-create complete"
echo "$(date +'%Y-%m-%d %H:%M:%S')    post-create complete" >> "$HOME/status"
