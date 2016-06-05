if !has('nvim')
  finish
endif

command! -bang NvimPythonCheck call python_diag#check(<bang>0)
