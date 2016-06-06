function! s:trim(s) abort
  return substitute(a:s, '^\_s*\|\_s*$', '', 'g')
endfunction


" Simple version comparison.
function! s:version_cmp(a, b) abort
  let a = split(a:a, '\.')
  let b = split(a:b, '\.')

  for i in range(len(a))
    if a[i] > b[i]
      return 1
    elseif a[i] < b[i]
      return -1
    endif
  endfor

  return 0
endfunction


" Fetch the contents of a URL.
function! s:download(url) abort
  let script = "
        \try:\n
        \    from urllib.request import urlopen\n
        \except ImportError:\n
        \    from urllib2 import urlopen\n
        \\n
        \try:\n
        \    response = urlopen('".a:url."')\n
        \    print(response.read().decode('utf8'))\n
        \except Exception:\n
        \    raise\n
        \"
  return systemlist('python -c "'.script.'"')
endfunction


" Get the latest Neovim Python client version from PyPI.  The result is
" cached.
function! s:latest_pypi_version()
  if exists('s:pypi_version')
    return s:pypi_version
  endif

  let s:pypi_version = 'unknown'
  let pypi_info = s:download('https://pypi.python.org/pypi/neovim/json')
  if !empty(pypi_info)
    let pypi_data = json_decode(pypi_info)
    let s:pypi_version = get(get(pypi_data, 'info', {}), 'version', 'unknown')
    return s:pypi_version
  endif
endfunction


" Get version information using the specified interpreter.  The interpreter is
" used directly in case breaking changes were introduced since the last time
" Neovim's Python client was updated.
function! s:version_info(python) abort
  let pypi_version = s:latest_pypi_version()
  let python_version = s:trim(system(
        \ printf('"%s" -c "import sys; print(''.''.join(str(x) '
        \ . 'for x in sys.version_info[:3]))"', a:python)))
  if empty(python_version)
    let python_version = 'unknown'
  endif
  
  let nvim_path = s:trim(system(printf('"%s" -c "import sys, neovim;'
        \ . 'print(neovim.__file__)" 2>/dev/null', a:python)))
  if empty(nvim_path)
    return [python_version, 'not found', pypi_version, 'unknown']
  endif

  let nvim_version = 'unknown'
  let base = fnamemodify(nvim_path, ':h')
  for meta in glob(base.'-*/METADATA', 1, 1) + glob(base.'-*/PKG-INFO', 1, 1)
    for meta_line in readfile(meta)
      if meta_line =~# '^Version:'
        let nvim_version = matchstr(meta_line, '^Version: \zs\S\+')
      endif
    endfor
  endfor

  let version_status = 'unknown'
  if nvim_version != 'unknown' && pypi_version != 'unknown'
    if s:version_cmp(nvim_version, pypi_version) == -1
      let version_status = 'outdated'
    else
      let version_status = 'up to date'
    endif
  endif

  return [python_version, nvim_version, pypi_version, version_status]
endfunction


" Check the Python interpreter's usability.
function! s:check_bin(bin, notes) abort
  if !filereadable(a:bin)
    call add(a:notes, printf('Error: "%s" was not found.', a:bin))
    return 0
  elseif executable(a:bin) != 1
    call add(a:notes, printf('Error: "%s" is not executable.', a:bin))
    return 0
  endif
  return 1
endfunction


" Text wrapping that returns a list of lines
function! s:textwrap(text, width) abort
  let pattern = '.*\%(\s\+\|\_$\)\zs\%<'.a:width.'c'
  return map(split(a:text, pattern), 's:trim(v:val)')
endfunction


" Echo wrapped notes
function! s:echo_notes(notes) abort
  if empty(a:notes)
    return
  endif

  echo '  Messages:'
  for msg in a:notes
    let msg_lines = s:textwrap(msg, 74)
    echo '    *' msg_lines[0]
    if len(msg_lines) > 1
      echo join(map(msg_lines[1:], '"      ".v:val'), "\n")
    endif
  endfor
endfunction


" Load the remote plugin manifest file and check for unregistered plugins
function! s:diagnose_manifest() abort
  echo 'Checking: Remote Plugins'
  let existing_rplugins = {}

  for item in remote#host#PluginsForHost('python')
    let existing_rplugins[item.path] = 'python'
  endfor

  for item in remote#host#PluginsForHost('python3')
    let existing_rplugins[item.path] = 'python3'
  endfor

  let require_update = 0
  let notes = []

  for path in map(split(&rtp, ','), 'resolve(v:val)')
    let python_glob = glob(path.'/rplugin/python*', 1, 1)
    if empty(python_glob)
      continue
    endif

    let python_dir = python_glob[0]
    let python_version = fnamemodify(python_dir, ':t')

    for script in glob(python_dir.'/*.py', 1, 1)
          \ + glob(python_dir.'/*/__init__.py', 1, 1)
      let contents = join(readfile(script))
      if contents =~# '\<\%(from\|import\)\s\+neovim\>'
        if script =~# '/__init__\.py$'
          let script = fnamemodify(script, ':h')
        endif

        if !has_key(existing_rplugins, script)
          let msg = printf('"%s" is not registered.', fnamemodify(path, ':t'))
          if python_version == 'pythonx'
            if !has('python2') && !has('python3')
              let msg .= ' (python2 and python3 not available)'
            endif
          elseif !has(python_version)
            let msg .= printf(' (%s not available)', python_version)
          else
            let require_update = 1
          endif

          call add(notes, msg)
        endif

        break
      endif
    endfor
  endfor

  echo '  Status: '
  if require_update
    echon 'Out of date'
    call add(notes, 'Run :UpdateRemotePlugins')
  else
    echon 'Up to date'
  endif

  call s:echo_notes(notes)
endfunction


function! s:diagnose_python(version) abort
  let python_bin_name = 'python'.(a:version == 2 ? '' : '3')
  let pyenv = resolve(exepath('pyenv'))
  let pyenv_root = exists('$PYENV_ROOT') ? resolve($PYENV_ROOT) : ''
  let venv = exists('$VIRTUAL_ENV') ? resolve($VIRTUAL_ENV) : ''
  let host_prog_var = python_bin_name.'_host_prog'
  let python_bin = ''
  let python_multiple = []
  let notes = []

  if exists('g:'.host_prog_var)
    let python_bin = get(g:, host_prog_var)
    call add(notes, printf('Using: g:%s = "%s"', host_prog_var, python_bin))
  else
    call add(notes, printf('Warning: "g:%s" is not set.  Searching for '
          \ . '%s in the environment.', host_prog_var, python_bin_name))
    if !empty(pyenv)
      if empty(pyenv_root)
        call add(notes, 'Warning: pyenv was found, but $PYENV_ROOT '
              \ . 'is not set.  Did you follow the final install '
              \ . 'instructions?')
      else
        call add(notes, printf('Notice: pyenv found: "%s"', pyenv))
      endif

      let python_bin = s:trim(system(
            \ printf('"%s" which %s 2>/dev/null', pyenv, python_bin_name)))

      if empty(python_bin)
        call add(notes, printf('Warning: pyenv couldn''t find %s.', python_bin_name))
      endif
    endif

    if empty(python_bin)
      let python_bin = exepath(python_bin_name)

      if exists('$PATH')
        for path in split($PATH, ':')
          let path_bin = path.'/'.python_bin_name
          if path_bin != python_bin && index(python_multiple, path_bin) == -1
                \ && executable(path_bin)
            call add(python_multiple, path_bin)
          endif
        endfor

        if len(python_multiple)
          " This is worth noting since the user may install something
          " that changes $PATH, like homebrew.
          call add(notes, printf('Suggestion: There are multiple %s executables found.  '
                \ . 'Set "g:%s" to avoid surprises.', python_bin_name, host_prog_var))
        endif

        if python_bin =~# '\<shims\>'
          call add(notes, printf('Warning: "%s" appears to be a pyenv shim.  '
                \ . 'This could mean that a) the "pyenv" executable is not in '
                \ . '$PATH, b) your pyenv installation is broken.  '
                \ . 'You should set "g:%s" to avoid surprises.',
                \ python_bin, host_prog_var))
        endif
      endif
    endif
  endif

  if !empty(python_bin)
    if !empty(pyenv) && !exists('g:'.host_prog_var) && !empty(pyenv_root)
          \ && resolve(python_bin) !~# '^'.pyenv_root.'/'
      call add(notes, printf('Suggestion: Create a virtualenv specifically '
            \ . 'for Neovim using pyenv and use "g:%s".  This will avoid '
            \ . 'the need to install Neovim''s Python client in each '
            \ . 'version/virtualenv.', host_prog_var))
    endif

    if !empty(venv) && exists('g:'.host_prog_var)
      if !empty(pyenv_root)
        let venv_root = pyenv_root
      else
        let venv_root = fnamemodify(venv, ':h')
      endif

      if resolve(python_bin) !~# '^'.venv_root.'/'
        call add(notes, printf('Suggestion: Create a virtualenv specifically '
              \ . 'for Neovim and use "g:%s".  This will avoid '
              \ . 'the need to install Neovim''s Python client in each '
              \ . 'virtualenv.', host_prog_var))
      endif
    endif
  endif

  if empty(python_bin)
    call add(notes, printf('Error: "%s" was not found.', python_bin_name))
  elseif !s:check_bin(python_bin, notes)
    let python_bin = ''
  endif

  " Check if $VIRTUAL_ENV is active
  let virtualenv_inactive = 0

  if exists('$VIRTUAL_ENV')
    if !empty(pyenv)
      let pyenv_prefix = resolve(s:trim(system(printf('"%s" prefix', pyenv))))
      if $VIRTUAL_ENV != pyenv_prefix
        let virtualenv_inactive = 1
      endif
    elseif exepath(python_bin_name) !~# '^'.$VIRTUAL_ENV.'/'
      let virtualenv_inactive = 1
    endif
  endif

  if virtualenv_inactive
    call add(notes, 'Warning: $VIRTUAL_ENV exists but appears to be '
          \ . 'inactive.  This could lead to unexpected results.  If you are '
          \ . 'using Zsh, see: http://vi.stackexchange.com/a/7654/5229')
  endif

  " Diagnostic output
  echo 'Checking: Python' a:version
  echo '  Executable:' (empty(python_bin) ? 'Not found' : python_bin)
  if len(python_multiple)
    for path_bin in python_multiple
      echo '     (other):' path_bin
    endfor
  endif

  if !empty(python_bin)
    let [pyversion, current, latest, status] = s:version_info(python_bin)
    if a:version != str2nr(pyversion)
      call add(notes, 'Warning: Got an unexpected version of Python.  '
            \ . 'This could lead to confusing error messages.  Please '
            \ . 'consider this before reporting bugs to plugin developers.')
    endif
    if a:version == 3 && str2float(pyversion) < 3.3
      call add(notes, 'Warning: Python 3.3+ is recommended.')
    endif

    echo '  Python Version:' pyversion
    echo '  Neovim Version:' current

    if current == 'not found'
      call add(notes, 'Error: Neovim Python client is not installed.')
    endif

    if latest == 'unknown'
      call add(notes, 'Warning: Unable to fetch latest Neovim Python client version.')
    endif

    if status == 'outdated'
      echon ' (latest: '.latest.')'
    elseif status == 'unknown'
    else
      echon ' ('.status.')'
    endif
  endif

  call s:echo_notes(notes)
endfunction


function! nvimdiagnostic#python#check(bang) abort
  redir => report
  try
    silent call s:diagnose_python(2)
    silent echo ''
    silent call s:diagnose_python(3)
    silent echo ''
    silent call s:diagnose_manifest()
    silent echo ''
  finally
    redir END
  endtry

  if a:bang
    new
    setlocal bufhidden=wipe
    call setline(1, split(report, "\n"))
    setlocal nomodified
  else
    echo report
    echo "\nTip: Use "
    echohl Identifier
    echon ":NvimPythonCheck!"
    echohl None
    echon " to open this in a new buffer."
  endif
endfunction
