# azure-dev-terminal shell setup (sourced from ~/.bashrc)
# tmux reattach-or-new: survives SSH disconnects (NOT VM deallocation).
alias ta='tmux attach -t main 2>/dev/null || tmux new -s main'
