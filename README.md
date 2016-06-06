# Neovim Python Diagnosis

Checks for Python setup problems in Neovim.

## Usage

`:NvimPythonCheck` to print information.  `:NvimPythonCheck!` to put the
information in a new buffer.


## Example output

```
Checking: Python 2
  Executable: /home/tallen/.linuxbrew/bin/python
  Python Version: 2.7.11
  Neovim Version: 0.1.8 (up to date)
  Messages:
    * Warning: "g:python_host_prog" is not set.  Searching for python in the
      environment.
    * pyenv found: "/home/tallen/.local/pyenv/libexec/pyenv"
    * Suggestion: Create a virtualenv specifically for Neovim using pyenv and
      use "g:python_host_prog".  This will avoid the need to install Neovim's
      Python client in each version/virtualenv.

Checking: Python 3
  Executable: /usr/bin/python3
  Python Version: 3.4.3
  Neovim Version: not found
  Messages:
    * Warning: "g:python3_host_prog" is not set.  Searching for python3 in
      the environment.
    * pyenv found: "/home/tallen/.local/pyenv/libexec/pyenv"
    * Suggestion: Create a virtualenv specifically for Neovim using pyenv and
      use "g:python3_host_prog".  This will avoid the need to install
      Neovim's Python client in each version/virtualenv.
    * Error: Neovim Python client is not installed.

Checking: Remote Plugins
  Status: Out of date
  Messages:
    * "deoplete.nvim" is not registered.
    * Run :UpdateRemotePlugins
```
