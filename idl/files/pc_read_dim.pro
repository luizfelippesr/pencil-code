; $Id: pc_read_dim.pro,v 1.8 2004-05-05 17:10:31 mee Exp $
;
;   Read stuff from dim.dat
;
;  Author: Tony Mee (A.J.Mee@ncl.ac.uk)
;  $Date: 2004-05-05 17:10:31 $
;  $Revision: 1.8 $
;
;  27-nov-02/tony: coded 
;
;  
pro pc_read_dim, mx=mx, my=my, mz=mz, mvar=mvar, $
                 nx=nx, ny=ny, nz=nz, $
                 nxgrid=nxgrid, nygrid=nygrid, nzgrid=nzgrid, $
                 mxgrid=mxgrid, mygrid=mygrid, mzgrid=mzgrid, $
                 precision=precision, $
                 nghostx=nghostx, nghosty=nghosty, nghostz=nghostz, $
                 nprocx=nprocx, nprocy=nprocy, nprocz=nprocz,$
                 l1=l1, l2=l2, m1=m1, m2=m2, n1=n1, n2=n2, $ 
                 object=object, $ 
                 datadir=datadir,proc=proc,PRINT=PRINT,QUIET=QUIET,HELP=HELP
COMPILE_OPT IDL2,HIDDEN
;
;  Read dim.dat
;
; If no meaningful parameters are given show some help!
  IF ( keyword_set(HELP) ) THEN BEGIN
    print, "Usage: "
    print, ""
    print, "pc_read_dim, mx=mx, my=my, mz=mz, mvar=mvar,                                                "
    print, "             nx=nx, ny=ny, nz=nz,                                                           "
    print, "             mxgrid=mxgrid, mygrid=mygrid, mzgrid=mzgrid,                                   "
    print, "             nxgrid=nxgrid, nygrid=nygrid, nzgrid=nzgrid,                                   "
    print, "             precision=precision,                                                           "
    print, "             nghostx=nghostx, nghosty=nghosty, nghostz=nghostz,                             "
    print, "             nprocx=nprocx, nprocy=nprocy, nprocz=nprocz,                                   "
    print, "             object=object,                                                                 "
    print, "             datadir=datadir, proc=proc, /PRINT, /QUIET, /HELP                              "
    print, "                                                                                            "
    print, "Returns the run dimensions of a Pencil-Code run.  Either for the whole calculation,         "
    print, "or if `proc' is defined then for a specific processor.                                      "
    print, "Returns zeros and empty in all variables on failure.                                        "
    print, "                                                                                            "
    print, "  datadir: specify the root data directory. Default is './data'                     [string]"
    print, "     proc: specify a processor to get the data from eg. 0                          [integer]"
    print, "           If unspecified data is read for global calculation.                              "
    print, "                                                                                            "
    print, "       mx: x dimension of processor calculation domain including ghost zones       [integer]"
    print, "       my: y dimension of processor calculation domain including ghost zones       [integer]"
    print, "       mz: z dimension of processor calculation domain including ghost zones       [integer]"
    print, "       mw: defined as mx * my * mz                                                 [integer]"
    print, "       nx: x dimension of processor calculation domain excluding ghost zones       [integer]"
    print, "       ny: y dimension of processor calculation domain excluding ghost zones       [integer]"
    print, "       nz: z dimension of processor calculation domain excluding ghost zones       [integer]"
    print, "   nxgrid: x dimension of full calculation domain excluding ghost zones            [integer]"
    print, "   nygrid: y dimension of full calculation domain excluding ghost zones            [integer]"
    print, "   nzgrid: z dimension of full calculation domain excluding ghost zones            [integer]"
    print, "   mxgrid: x dimension of full calculation domain including ghost zones            [integer]"
    print, "   mygrid: y dimension of full calculation domain including ghost zones            [integer]"
    print, "   mzgrid: z dimension of full calculation domain including ghost zones            [integer]"
    print, "     mvar: total number of computed scalar variables (NB. 1 vector = 3 scalars)    [integer]"
    print, "precision: 'S' or 'D' for Single or Double precision                             [character]"
    print, "  nghostx: number of points in x direction used for ghost zone at each boundary    [integer]"
    print, "  nghosty: number of points in y direction used for ghost zone at each boundary    [integer]"
    print, "  nghostx: number of points in z direction used for ghost zone at each boundary    [integer]"
    print, "   nprocx: number of communicating processors in the x direction                   [integer]"
    print, "   nprocy: number of communicating processors in the y direction                   [integer]"
    print, "   nprocz: number of communicating processors in the z direction                   [integer]"
    print, "   l1, l2: first & last index of non-ghost-point in x                              [integer]"
    print, "   m1, m2: first & last index of non-ghost-point in y                              [integer]"
    print, "   n1, n2: first & last index of non-ghost-point in z                              [integer]"
    print, ""
    print, "   object: optional structure in which to return all the above as tags           [structure]"
    print, ""
    print, "   /PRINT: instruction to print all variables to standard output                            "
    print, "   /QUIET: instruction not to print any 'helpful' information                               "
    print, "    /HELP: display this usage information, and exit                                         "
    return
  ENDIF

; Default data directory

default, datadir, 'data'

;
; Initialize / set default returns for ALL variables
;
mx=0L
my=0L
mz=0L
mw=0L
mvar=0L
precision=''
nx=0L
ny=0L
nz=0L
nghostx=0L
nghosty=0L
nghostz=0L
nprocx=0L
nprocy=0L
nprocz=0L

; Get a unit number
GET_LUN, file

; Build the full path and filename
if keyword_set(proc) then begin
    filename=datadir+'/proc'+str(proc)+'/dim.dat'   ; Read processor box dimensions
endif else begin
    filename=datadir+'/dim.dat'            ; Read global box dimensions
endelse

; Check for existance and read the data
dummy=findfile(filename, COUNT=found)
if (found gt 0) then begin
  IF ( not keyword_set(QUIET) ) THEN print, 'Reading ' + filename + '...'

  openr,file,filename
  readf,file,mx,my,mz,mvar
  readf,file,precision
  readf,file,nghostx,nghosty,nghostz
  readf,file,nprocx,nprocy,nprocz
  close,file 
  FREE_LUN,file
end else begin
  message, 'ERROR: cannot find file ' + filename
end

; Calculate any derived quantities
nx = mx - (2 * nghostx)
ny = my - (2 * nghosty)
nz = mz - (2 * nghostz)
mw = mx * my * mz
l1 = nghostx & l2 = mx-nghostx
m1 = nghosty & m2 = my-nghosty
n1 = nghostz & n2 = mz-nghostz

nxgrid=nx*nprocx
nygrid=ny*nprocy
nzgrid=nz*nprocz

mxgrid = nxgrid + (2 * nghostx)
mygrid = nygrid + (2 * nghosty)
mzgrid = nzgrid + (2 * nghostz)

precision = (strtrim(precision,2))        ; drop leading zeros
precision = strmid(precision,0,1)


; Build structure of all the variables
object = CREATE_STRUCT(name=filename,['mx','my','mz','mw','mvar', $
                        'precision', $
                        'nx','ny','nz', $
                        'nghostx','nghosty','nghostz', $
                        'nxgrid','nygrid','nzgrid', $
                        'mxgrid','mygrid','mzgrid', $
                        'nprocx','nprocy','nprocz'], $
                       mx,my,mz,mw,mvar,precision,nx,ny,nz,nghostx,nghosty,nghostz, $
                       nxgrid, nygrid, nzgrid, $
                       mxgrid, mygrid, mzgrid, $
                       nprocx,nprocy,nprocz)


; If requested print a summary
if keyword_set(PRINT) then begin
  if keyword_set(proc) then begin
      print, 'For processor ',proc,' calculation domain:'
  endif else begin
      print, 'For GLOBAL calculation domain:'
  endelse

  print, '          (mx,my,mz,mvar) = (',mx,',',my,',',mz,',',mvar,')'
  print, '                       mw = ',mw
  print, '               (nx,ny,nz) = (',nx,',',ny,',',nz,')'
  print, '                precision = ', precision
  print, '(nghostx,nghosty,nghostz) = (',nghostx,',',nghosty,',',nghostz,')'
  print, '   (nxgrid,nygrid,nzgrid) = (',nxgrid,',',nygrid,',',nzgrid,')'
  print, '   (mxgrid,mygrid,mzgrid) = (',mxgrid,',',mygrid,',',mzgrid,')'
  print, '   (nprocx,nprocy,nprocz) = (',nprocx,',',nprocy,',',nprocz,')'
endif

end
