vim9script

# A real native terminal supplies the grid; Ex-mode 'columns' alone does not.
var child = term_start([v:progpath, '-Nu', 'NONE', '-U', 'NONE', '-i', 'NONE', '-n', '-N',
  '-V1' .. $DIFFVIEW_TEST_TMP .. '/history_preview.screen.log',
  '-S', expand('<sfile>:p:h') .. '/acceptance.vim'],
  {hidden: true, term_rows: 60, term_cols: 240})
var job = term_getjob(child)
var started = reltime()
while job_status(job) == 'run' && reltimefloat(reltime(started)) < 180
  term_wait(child, 20)
endwhile
writefile(getbufline(child, 1, '$'), $DIFFVIEW_TEST_TMP .. '/history_preview.screen')
if job_status(job) == 'run'
  job_stop(job, 'kill')
  cquit 1
endif
if get(job_info(job), 'exitval', -1) != 0
  cquit 1
endif
qa!
