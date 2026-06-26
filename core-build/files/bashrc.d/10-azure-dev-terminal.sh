# azure-dev-terminal shell setup (sourced from ~/.bashrc)
# tmux reattach-or-new: survives SSH disconnects (NOT VM deallocation).
alias ta='tmux attach -t main 2>/dev/null || tmux new -s main'
# System-wide npm globals (Copilot CLI) on PATH.
case ":$PATH:" in
  *":/usr/local/bin:"*) ;;
  *) export PATH="/usr/local/bin:$PATH" ;;
esac
# Copilot CLI terminal toggle inside LazyVim is <C-/> (fallback <C-t> / <leader>tt).
