! $Id: radiation_exp.f90,v 1.64 2003-07-10 13:22:17 theine Exp $

!!!  NOTE: this routine will perhaps be renamed to radiation_feautrier
!!!  or it may be combined with radiation_ray.

module Radiation

!  Radiation (solves transfer equation along rays)
!  The direction of the ray is given by the vector (lrad,mrad,nrad),
!  and the parameters radx0,rady0,radz0 gives the maximum number of
!  steps of the direction vector in the corresponding direction.

  use Cparam
!
  implicit none
!
  character (len=2*bclen+1), dimension(3) :: bc_rad=(/'0:0','0:0','S:0'/)
  character (len=bclen), dimension(3) :: bc_rad1,bc_rad2
  integer, parameter :: radx0=1,rady0=1,radz0=1
  real, dimension (mx,my,mz) :: Srad,kaprho,emtau,Irad,Irad0
  real, dimension(mx,my,mz,3) :: pos
  integer :: lrad,mrad,nrad,rad2
  integer :: directions
  real :: frac
  integer :: llstart,llstop,ldir
  integer :: mmstart,mmstop,mdir
  integer :: nnstart,nnstop,ndir
  integer :: l
  logical, dimension(3) :: lhori=.false.
!
!  default values for one pair of vertical rays
!
  integer :: radx=0,rady=0,radz=1,rad2max=1
!
  logical :: nocooling=.false.,test_radiation=.false.,output_Qrad=.false.
  logical :: lkappa_es=.false.
  logical :: axeltest=.false.
!
!  definition of dummy variables for FLD routine
!
  real :: DFF_new=0.  !(dum)
  integer :: i_frms=0,i_fmax=0,i_Erad_rms=0,i_Erad_max=0
  integer :: i_Egas_rms=0,i_Egas_max=0

  namelist /radiation_init_pars/ &
       radx,rady,radz,rad2max,output_Qrad,test_radiation,lkappa_es, &
       bc_rad,axeltest

  namelist /radiation_run_pars/ &
       radx,rady,radz,rad2max,output_Qrad,test_radiation,lkappa_es,nocooling, &
       bc_rad

  contains

!***********************************************************************
    subroutine register_radiation()
!
!  initialise radiation flags
!
!  24-mar-03/axel+tobi: coded
!
      use Cdata
      use Mpicomm
      use Sub
!
      logical, save :: first=.true.
!
      if(.not. first) call stop_it('register_radiation called twice')
      first = .false.
!
      lradiation=.true.
      lradiation_ray=.true.
!
!  set indices for auxiliary variables
!
      iQrad = mvar + naux +1; naux = naux + 1
!
      if ((ip<=8) .and. lroot) then
        print*, 'register_radiation: radiation naux = ', naux
        print*, 'iQrad = ', iQrad
      endif
!
!  identify version number (generated automatically by CVS)
!
      if (lroot) call cvs_id( &
           "$Id: radiation_exp.f90,v 1.64 2003-07-10 13:22:17 theine Exp $")
!
!  Check that we aren't registering too many auxilary variables
!
      if (nvar > mvar) then
        if (lroot) write(0,*) 'naux = ', naux, ', maux = ', maux
        call stop_it('register_radiation: naux > maux')
      endif
!
!  Writing files for use with IDL
!
      if (naux < maux) aux_var(aux_count)=',Qrad $'
      if (naux == maux) aux_var(aux_count)=',Qrad'
      aux_count=aux_count+1
      write(5,*) 'Qrad = fltarr(mx,my,mz)*one'
!
    endsubroutine register_radiation
!***********************************************************************
    subroutine initialize_radiation()
!
!  Calculate number of directions of rays
!  Do this in the beginning of each run
!
!  16-jun-03/axel+tobi: coded
!  03-jul-03/tobi: position array added
!
      use Cdata
      use Sub
!
!  check that the number of rays does not exceed maximum
!
      if(radx>radx0) stop "radx0 is too small"
      if(rady>rady0) stop "rady0 is too small"
      if(radz>radz0) stop "radz0 is too small"
!
!  count
!
      directions=0
      do nrad=-radz,radz
      do mrad=-rady,rady
      do lrad=-radx,radx
        rad2=lrad**2+mrad**2+nrad**2
        if(rad2>0 .and. rad2<=rad2max) then 
          directions=directions+1
        endif
      enddo
      enddo
      enddo
!
      print*,'initialize_radiation: directions=',directions
!
!  initialize position array
!
      do l=1,mx
      do m=1,my
      do n=1,mz
         pos(l,m,n,1)=l
         pos(l,m,n,2)=m
         pos(l,m,n,3)=n
      enddo
      enddo
      enddo
!
!  check boundary conditions
!
      print*,'bc_rad=',bc_rad
      call parse_bc_rad(bc_rad,bc_rad1,bc_rad2)
      print*,'bc_rad1,bc_rad2=',bc_rad1,bc_rad2
!
    endsubroutine initialize_radiation
!***********************************************************************
    subroutine radcalc(f)
!
!  calculate source function and opacity
!
!  24-mar-03/axel+tobi: coded
!
      use Cdata
      use Ionization
!
      real, dimension(mx,my,mz,mvar+maux), intent(in) :: f
      real :: k
!
!  test
!
      if(test_radiation) then
        if(lroot.and.ip<12) print*,'radcalc: put Srad=kaprho=1 (as a test)'
        k=2*pi/Lx
        Srad=1.+.02*spread(spread(cos(k*x),2,my),3,mz) &
                   *spread(spread(cos(k*y),1,mx),3,mz)
        kaprho=spread(spread(cos(2*k*x),2,my),3,mz) &
              *spread(spread(cos(2*k*y),1,mx),3,mz)
        Srad=1
        kaprho=1
        return
      endif
!
!  At the moment we don't calculate ghost zones (ok for vertical arrays)  
!
      do n=n0,n3
      do m=m0,m3
         call sourcefunction(f,Srad)
!
!  opacity: if lkappa_es then take electron scattering opacity only;
!  otherwise use Hminus opacity (but may need to add kappa_es as well).
!
         if (lkappa_es) then
            kaprho(l0:l3,m,n)=kappa_es*exp(f(l0:l3,m,n,ilnrho))
         else
            call opacity(f,kaprho)
         endif
      enddo
      enddo
!
    endsubroutine radcalc
!***********************************************************************
    subroutine radtransfer(f)
!
!  Integration radioation transfer equation along rays
!
!  This routine is called before the communication part
!  (certainly needs to be given a better name)
!  All rays start with zero intensity
!
!  16-jun-03/axel+tobi: coded
!
      use Cdata
!
      real, dimension(mx,my,mz,mvar+maux) :: f
!
!  identifier
!
      if(lroot.and.headt) print*,'radtransfer'
!
!  calculate source function and opacity
!
      call radcalc(f)
!
!  Accumulate the result for Qrad=(J-S),
!  First initialize Qrad=-S. 
!
      f(:,:,:,iQrad)=-Srad
      if(axeltest) f(:,:,:,iQrad)=0
!
!  calculate weights
!
      frac=1./directions
!
!  loop over rays
!
      do nrad=-radz,radz
      do mrad=-rady,rady
      do lrad=-radx,radx
        rad2=lrad**2+mrad**2+nrad**2
        if (rad2>0 .and. rad2<=rad2max) then 
!
           if (lrad>=0) then; llstart=l1; llstop=l2; ldir=+1
                        else; llstart=l2; llstop=l1; ldir=-1; endif
           if (mrad>=0) then; mmstart=m1; mmstop=m2; mdir=+1
                        else; mmstart=m2; mmstop=m1; mdir=-1; endif
           if (nrad>=0) then; nnstart=n1; nnstop=n2; ndir=+1
                        else; nnstart=n2; nnstop=n1; ndir=-1; endif
!
           call intensity_intrinsic(f)
           call intensity_periodic()
           call intensity_communicate()
           call intensity_revision(f)
!
        endif
      enddo
      enddo
      enddo
!
    endsubroutine radtransfer
!***********************************************************************
    subroutine intensity_intrinsic(f)
!
!  Integration radiation transfer equation along rays
!
!  This routine is called before the communication part
!  All rays start with zero intensity
!
!  16-jun-03/axel+tobi: coded
!
      use Cdata
!
      real, dimension(mx,my,mz,mvar+maux) :: f
      real :: dlength,dtau,emdtau
!
!  identifier
!
      if(lroot.and.headt) print*,'intensity_intrinsic'
!
!  line elements
!
      dlength=sqrt((dx*lrad)**2+(dy*mrad)**2+(dz*nrad)**2)
!
!  set optical depth and intensity initially to zero
!
      emtau=1.
      Irad=0.
!
!  loop
!
      do n=nnstart,nnstop,ndir
      do m=mmstart,mmstop,mdir
      do l=llstart,llstop,ldir 
          dtau=.5*(kaprho(l-lrad,m-mrad,n-nrad)+kaprho(l,m,n))*dlength
          emdtau=exp(-dtau)
          emtau(l,m,n)=emtau(l-lrad,m-mrad,n-nrad)*emdtau
          pos(l,m,n,:)=pos(l-lrad,m-mrad,n-nrad,:)
          Irad(l,m,n)=Irad(l-lrad,m-mrad,n-nrad)*emdtau &
                      +(1.-emdtau)*Srad(l-lrad,m-mrad,n-nrad) &
                      +(emdtau-1+dtau)*(Srad(l,m,n) &
                                       -Srad(l-lrad,m-mrad,n-nrad))/dtau
      enddo
      enddo
      enddo
!
!  add contribution to the heating rate Q
!
      f(:,:,:,iQrad)=f(:,:,:,iQrad)+frac*Irad
!
    endsubroutine intensity_intrinsic
!***********************************************************************
    subroutine intensity_periodic()
!
      use Cdata
      use Mpicomm
!
      real, dimension(radx0,my,mz) :: Irad0_yz,emtau0_yz
      real, dimension(mx,rady0,mz) :: Irad0_zx,emtau0_zx
      real, dimension(mx,my,radz0) :: Irad0_xy,emtau0_xy
!
!  x-direction
!
      if (lrad>0.and.bc_rad1(1)=='p') then
        if (ipx==0) then
          Irad0_yz=0
          emtau0_yz=1
        else
          call radboundary_yz_recv(radx0,ipx-1,Irad0_yz,emtau0_yz)
        endif
        Irad0_yz=Irad0_yz*emtau(l2-radx0+1:l2,:,:)+Irad(l2-radx0+1:l2,:,:)
        emtau0_yz=emtau0_yz*emtau(l2-radx0+1:l2,:,:)
        if (ipx==nprocx-1) then
          Irad0_yz=Irad0_yz/(1-emtau0_yz)
          call radboundary_yz_send(radx0,0,Irad0_yz)
        else
          call radboundary_yz_send(radx0,ipx+1,Irad0_yz,emtau0_yz)
        endif 
      endif
!
      if (lrad<0.and.bc_rad2(1)=='p') then
        if (ipx==nprocx-1) then
          Irad0_yz=0
          emtau0_yz=1
        else
          call radboundary_yz_recv(radx0,ipx+1,Irad0_yz,emtau0_yz)
        endif
        Irad0_yz=Irad0_yz*emtau(l1:l1+radx0-1,:,:)+Irad(l1:l1+radx0-1,:,:)
        emtau0_yz=emtau0_yz*emtau(l1:l1+radx0-1,:,:)
        if (ipx==0) then
          Irad0_yz=Irad0_yz/(1-emtau0_yz)
          call radboundary_yz_send(radx0,nprocx-1,Irad0_yz)
        else
          call radboundary_yz_send(radx0,ipx-1,Irad0_yz,emtau0_yz)
        endif 
      endif
!
!  y-direction
!
      if (mrad>0.and.bc_rad1(2)=='p') then
        if (ipy==0) then
          Irad0_zx=0
          emtau0_zx=1
        else
          call radboundary_zx_recv(rady0,ipy-1,Irad0_zx,emtau0_zx)
        endif
        Irad0_zx=Irad0_zx*emtau(:,m2-rady0+1:m2,:)+Irad(:,m2-rady0+1:m2,:)
        emtau0_zx=emtau0_zx*emtau(:,m2-rady0+1:m2,:)
        if (ipy==nprocy-1) then
          Irad0_zx=Irad0_zx/(1-emtau0_zx)
          call radboundary_zx_send(rady0,0,Irad0_zx)
        else
          call radboundary_zx_send(rady0,ipy+1,Irad0_zx,emtau0_zx)
        endif 
      endif
!
      if (mrad<0.and.bc_rad2(2)=='p') then
        if (ipy==nprocy-1) then
          Irad0_zx=0
          emtau0_zx=1
        else
          call radboundary_zx_recv(rady0,ipy+1,Irad0_zx,emtau0_zx)
        endif
        Irad0_zx=Irad0_zx*emtau(:,m1:m1+rady0-1,:)+Irad(:,m1:m1+rady0-1,:)
        emtau0_zx=emtau0_zx*emtau(:,m1:m1+rady0-1,:)
        if (ipy==0) then
          Irad0_zx=Irad0_zx/(1-emtau0_zx)
          call radboundary_zx_send(rady0,nprocy-1,Irad0_zx)
        else
          call radboundary_zx_send(rady0,ipy-1,Irad0_zx,emtau0_zx)
        endif 
      endif
!
!  z-direction
!
      if (nrad>0.and.bc_rad1(3)=='p') then
        if (ipz==0) then
          Irad0_xy=0
          emtau0_xy=1
        else
          call radboundary_xy_recv(radz0,ipz-1,Irad0_xy,emtau0_xy)
        endif
        Irad0_xy=Irad0_xy*emtau(:,:,n2-radz0+1:n2)+Irad(:,:,n2-radz0+1:n2)
        emtau0_xy=emtau0_xy*emtau(:,:,n2-radz0+1:n2)
        if (ipz==nprocz-1) then
          Irad0_xy=Irad0_xy/(1-emtau0_xy)
          call radboundary_xy_send(radz0,0,Irad0_xy)
        else
          call radboundary_xy_send(radz0,ipz+1,Irad0_xy,emtau0_xy)
        endif 
      endif
      if (nrad<0.and.bc_rad2(3)=='p') then
        if (ipz==nprocz-1) then
          Irad0_xy=0
          emtau0_xy=1
        else
          call radboundary_xy_recv(radz0,ipz+1,Irad0_xy,emtau0_xy)
        endif
        Irad0_xy=Irad0_xy*emtau(:,:,n1:n1+radx0-1)+Irad(:,:,n1:n1+radx0-1)
        emtau0_xy=emtau0_xy*emtau(:,:,n1:n1+radx0-1)
        if (ipz==0) then
          Irad0_xy=Irad0_xy/(1-emtau0_xy)
          call radboundary_xy_send(radz0,nprocz-1,Irad0_xy)
        else
          call radboundary_xy_send(radz0,ipz-1,Irad0_xy,emtau0_xy)
        endif 
      endif
!
    endsubroutine intensity_periodic
!***********************************************************************
    subroutine intensity_communicate()
!
!  Integration radioation transfer equation along rays
!
!  This routine is called after the communication part
!  The true boundary intensities I0 are now known and
!    the correction term I0*exp(-tau) is added
!  16-jun-03/axel+tobi: coded
!
      use Cdata
!
!  identifier
!
      if(lroot.and.headt) print*,'intensity_communicate'
!
!  receive boundary values
!
      call receive_intensity()
!
!  propagate boundary values
!
      call propagate_intensity()
!
!  send boundary values
!
      call send_intensity()
!
    endsubroutine intensity_communicate
!***********************************************************************
    subroutine receive_intensity()
!
      use Cdata
      use Mpicomm
!
      real, dimension(radx0,my,mz) :: Irad0_yz
      real, dimension(mx,rady0,mz) :: Irad0_zx
      real, dimension(mx,my,radz0) :: Irad0_xy
!
!  identifier
!
      if(lroot.and.headt) print*,'receive_intensity'
!
!  ... in the x-direction
!
      if (lrad>0) then
        if (ipx==0) call radboundary_yz_set(Irad0_yz)
        if (ipx/=0) call radboundary_yz_recv(radx0,ipx-1,Irad0_yz)
        Irad0(l1-radx0:l1-1,:,:)=Irad0_yz
      endif
      if (lrad<0) then
        if (ipx==nprocx-1) call radboundary_yz_set(Irad0_yz)
        if (ipx/=nprocx-1) call radboundary_yz_recv(radx0,ipx+1,Irad0_yz)
        Irad0(l2+1:l2+radx0,:,:)=Irad0_yz
      endif
!
!  ... in the y-direction
!
      if (mrad>0) then
        if (ipy==0) call radboundary_zx_set(Irad0_zx)
        if (ipy/=0) call radboundary_zx_recv(rady0,ipy-1,Irad0_zx)
        Irad0(:,m1-rady0:m1-1,:)=Irad0_zx
      endif
      if (mrad<0) then
        if (ipy==nprocy-1) call radboundary_zx_set(Irad0_zx)
        if (ipy/=nprocy-1) call radboundary_zx_recv(rady0,ipy+1,Irad0_zx)
        Irad0(:,m2+1:m2+rady0,:)=Irad0_zx
      endif
!
!  ... in the z-direction
!
      if (nrad>0) then
        if (ipz==0) call radboundary_xy_set(Irad0_xy)
        if (ipz/=0) call radboundary_xy_recv(radz0,ipz-1,Irad0_xy)
        Irad0(:,:,n1-radz0:n1-1)=Irad0_xy
      endif
      if (nrad<0) then
        if (ipz==nprocz-1) call radboundary_xy_set(Irad0_xy)
        if (ipz/=nprocz-1) call radboundary_xy_recv(radz0,ipz+1,Irad0_xy)
        Irad0(:,:,n2+1:n2+radz0)=Irad0_xy
      endif
!
    endsubroutine receive_intensity
!***********************************************************************
    subroutine propagate_intensity()
!
!  In order to communicate the correct boundary intensities for each ray
!  to the next processor, we need to know the corresponding boundary
!  intensities of this one.
!
!  03-jul-03/tobi: coded
!
      use Cdata
!
      integer :: ll,mm,nn
!
!  identifier
!
      if(lroot.and.headt) print*,'propagate_intensity'
!
!  initialize position array in ghost zones
!
      do l=llstop-ldir*radx0+ldir,llstop,ldir
      do m=m1,m2
      do n=n1,n2
         ll=pos(l,m,n,1)
         mm=pos(l,m,n,2)
         nn=pos(l,m,n,3)
         Irad0(l,m,n)=Irad0(ll,mm,nn)
      enddo
      enddo
      enddo
      do l=l1,l2
      do m=mmstop-mdir*rady0+mdir,mmstop,mdir
      do n=n1,n2
         ll=pos(l,m,n,1)
         mm=pos(l,m,n,2)
         nn=pos(l,m,n,3)
         Irad0(l,m,n)=Irad0(ll,mm,nn)
      enddo
      enddo
      enddo
      do l=l1,l2
      do m=m1,m2
      do n=nnstop-ndir*radz0+ndir,nnstop,ndir
         ll=pos(l,m,n,1)
         mm=pos(l,m,n,2)
         nn=pos(l,m,n,3)
         Irad0(l,m,n)=Irad0(ll,mm,nn)
      enddo
      enddo
      enddo
!
    endsubroutine propagate_intensity
!***********************************************************************
    subroutine send_intensity()
!
      use Cdata
      use Mpicomm
!
      real, dimension(radx0,my,mz) :: Irad0_yz
      real, dimension(mx,rady0,mz) :: Irad0_zx
      real, dimension(mx,my,radz0) :: Irad0_xy
!
!  identifier
!
      if(lroot.and.headt) print*,'send_intensity'
!
!  ... in the x-direction
!
      if (lrad>0.and.ipx/=nprocx-1) then
        Irad0_yz=Irad0(l2-radx0+1:l2,:,:) &
                *emtau(l2-radx0+1:l2,:,:) &
                 +Irad(l2-radx0+1:l2,:,:)
        call radboundary_yz_send(radx0,ipx+1,Irad0_yz)
      endif
      if (lrad<0.and.ipx/=0) then
        Irad0_yz=Irad0(l1:l1+radx0-1,:,:) &
                *emtau(l1:l1+radx0-1,:,:) &
                 +Irad(l1:l1+radx0-1,:,:)
        call radboundary_yz_send(radx0,ipx-1,Irad0_yz)
      endif
!
!  ... in the y-direction
!
      if (mrad>0.and.ipy/=nprocy-1) then
        Irad0_zx=Irad0(:,m2-rady0+1:m2,:) &
                *emtau(:,m2-rady0+1:m2,:) &
                 +Irad(:,m2-rady0+1:m2,:)
        call radboundary_zx_send(rady0,ipy+1,Irad0_zx)
      endif
      if (mrad<0.and.ipy/=0) then
        Irad0_zx=Irad0(:,m1:m1+rady0-1,:) &
                *emtau(:,m1:m1+rady0-1,:) &
                 +Irad(:,m1:m1+rady0-1,:)
        call radboundary_zx_send(rady0,ipy-1,Irad0_zx)
      endif
!
!  ... in the z-direction
!
      if (nrad>0.and.ipz/=nprocz-1) then
        Irad0_xy=Irad0(:,:,n2-radz0+1:n2) &
                *emtau(:,:,n2-radz0+1:n2) &
                 +Irad(:,:,n2-radz0+1:n2)
        call radboundary_xy_send(radz0,ipz+1,Irad0_xy)
      endif
      if (nrad<0.and.ipz/=0) then
        Irad0_xy=Irad0(:,:,n1:n1+radz0-1) &
                *emtau(:,:,n1:n1+radz0-1) &
                 +Irad(:,:,n1:n1+radz0-1)
        call radboundary_xy_send(radz0,ipz-1,Irad0_xy)
      endif
!
    end subroutine send_intensity
!***********************************************************************
    subroutine radboundary_yz_set(Irad0_yz)
!
!  sets the physical boundary condition on xy plane
!
!   6-jul-03/axel: coded
!
      use Cdata
      use Mpicomm
!
      real, dimension(radx0,my,mz) :: Irad0_yz
!
!  lower x-boundary
!
    if (lrad>0) then
      select case(bc_rad1(1))
      case ('0'); Irad0_yz=0.
      case ('p'); call radboundary_yz_recv(radx0,nprocx-1,Irad0_yz)
      case ('S'); Irad0_yz=Srad(l1-radx0:l1-1,:,:)
      endselect
    endif
!
!  upper x-boundary
!
    if (lrad<0) then
      select case(bc_rad2(1))
      case ('0'); Irad0_yz=0.
      case ('p'); call radboundary_yz_recv(radx0,0,Irad0_yz)
      case ('S'); Irad0_yz=Srad(l2+1:l2+radx0,:,:)
      endselect
    endif
!
    endsubroutine radboundary_yz_set
!***********************************************************************
    subroutine radboundary_zx_set(Irad0_zx)
!
!  sets the physical boundary condition on xy plane
!
!   6-jul-03/axel: coded
!
    use Cdata
    use Mpicomm
!
    real, dimension(mx,rady0,mz) :: Irad0_zx
!
!
!  lower y-boundary
!
    if (mrad>0) then
      select case(bc_rad1(2))
      case ('0'); Irad0_zx=0.
      case ('p'); call radboundary_zx_recv(rady0,nprocy-1,Irad0_zx)
      case ('S'); Irad0_zx=Srad(:,m1-rady0:m1-1,:)
      endselect
    endif
!
!  upper y-boundary
!
    if (mrad<0) then
      select case(bc_rad2(2))
      case ('0'); Irad0_zx=0.
      case ('p'); call radboundary_zx_recv(rady0,0,Irad0_zx)
      case ('S'); Irad0_zx=Srad(:,m2+1:m2+rady0,:)
      endselect
    endif
!
    endsubroutine radboundary_zx_set
!***********************************************************************
    subroutine radboundary_xy_set(Irad0_xy)
!
!  sets the physical boundary condition on xy plane
!
!   6-jul-03/axel: coded
!
    use Cdata
    use Mpicomm
!
    real, dimension(mx,my,radz0) :: Irad0_xy
!
!  lower z-boundary
!
    if (nrad>0) then
      select case(bc_rad1(3))
      case ('0'); Irad0_xy=0.
      case ('p'); call radboundary_xy_recv(radz0,nprocz-1,Irad0_xy)
      case ('S'); Irad0_xy=Srad(:,:,n1-radz0:n1-1)
      endselect
    endif
!
!  upper z-boundary
!
    if (nrad<0) then
      select case(bc_rad2(3))
      case ('0'); Irad0_xy=0.
      case ('p'); call radboundary_xy_recv(radz0,0,Irad0_xy)
      case ('S'); Irad0_xy=Srad(:,:,n2+1:n2+radz0)
      endselect
    endif
!
    endsubroutine radboundary_xy_set
!***********************************************************************
    subroutine intensity_revision(f)
!
!  Integration radiation transfer equation along rays
!
!  This routine is called after the communication part
!  The true boundary intensities I0 are now known and
!    the correction term I0*exp(-tau) is added
!  16-jun-03/axel+tobi: coded
!
      use Cdata
!
      real, dimension(mx,my,mz,mvar+maux) :: f
!
!  identifier
!
      if(lroot.and.headt) print*,'intensity_revision'
!
!  do the ray...
!
      do n=nnstart,nnstop,ndir
      do m=mmstart,mmstop,mdir
      do l=llstart,llstop,ldir
          Irad0(l,m,n)=Irad0(l-lrad,m-mrad,n-nrad)
          Irad(l,m,n)=Irad0(l,m,n)*emtau(l,m,n)
      enddo
      enddo
      enddo
!
!  ...and add corresponding contribution to Q
!
      f(:,:,:,iQrad)=f(:,:,:,iQrad)+frac*Irad
!
    endsubroutine intensity_revision
!***********************************************************************
    subroutine radiative_cooling(f,df)
!
!  calculate source function
!
!  25-mar-03/axel+tobi: coded
!
      use Cdata
      use Ionization
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      real :: formfactor=0.5
!
!  Add radiative cooling
!
      do n=n1,n2
      do m=m1,m2
         if(.not. nocooling) then
            df(l1:l2,m,n,ient)=df(l1:l2,m,n,ient) &
                              +4.*pi*kaprho(l1:l2,m,n) &
                               *f(l1:l2,m,n,iQrad) &
                               /f(l1:l2,m,n,iTT)*formfactor &
                               *exp(-f(l1:l2,m,n,ilnrho))
         endif
      enddo
      enddo
!
    endsubroutine radiative_cooling
!***********************************************************************
    subroutine output_radiation(lun)
!
!  Optional output of derived quantities along with VAR-file
!  Called from wsnap
!
!   5-apr-03/axel: coded
!
      use Cdata
      use Ionization
!
      integer, intent(in) :: lun
!
!  identifier
!
      !if(lroot.and.headt) print*,'output_radiation',Qrad(4,4,4)
      !if(output_Qrad) write(lun) Qrad,Srad,kaprho,TT
!
    endsubroutine output_radiation
!***********************************************************************
    subroutine init_rad(f,xx,yy,zz)
!
!  Dummy routine for Flux Limited Diffusion routine
!  initialise radiation; called from start.f90
!
!  15-jul-2002/nils: dummy routine
!
      use Cdata
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz)      :: xx,yy,zz
!
      if(ip==0) print*,f,xx,yy,zz !(keep compiler quiet)
    endsubroutine init_rad
!***********************************************************************
   subroutine de_dt(f,df,rho1,divu,uu,uij,TT1,gamma)
!
!  Dummy routine for Flux Limited Diffusion routine
!
!  15-jul-2002/nils: dummy routine
!
      use Cdata
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      real, dimension (nx,3) :: uu
      real, dimension (nx) :: rho1,TT1
      real, dimension (nx,3,3) :: uij
      real, dimension (nx) :: divu
      real :: gamma
!
      if(ip==0) print*,f,df,rho1,divu,uu,uij,TT1,gamma !(keep compiler quiet)
    endsubroutine de_dt
!*******************************************************************
    subroutine rprint_radiation(lreset)
!
!  Dummy routine for Flux Limited Diffusion routine
!  reads and registers print parameters relevant for radiative part
!
!  16-jul-02/nils: adapted from rprint_hydro
!
      use Cdata
      use Sub
!  
      logical :: lreset
!
!  write column where which radiative variable is stored
!
      write(3,*) 'i_frms=',i_frms
      write(3,*) 'i_fmax=',i_fmax
      write(3,*) 'i_Erad_rms=',i_Erad_rms
      write(3,*) 'i_Erad_max=',i_Erad_max
      write(3,*) 'i_Egas_rms=',i_Egas_rms
      write(3,*) 'i_Egas_max=',i_Egas_max
      write(3,*) 'nname=',nname
      write(3,*) 'ie=',ie
      write(3,*) 'ifx=',ifx
      write(3,*) 'ify=',ify
      write(3,*) 'ifz=',ifz
      write(3,*) 'iQrad=',iQrad
!   
      if(ip==0) print*,lreset  !(to keep compiler quiet)
    endsubroutine rprint_radiation
!***********************************************************************
    subroutine  bc_ee_inflow_x(f,topbot)
!
!  Dummy routine for Flux Limited Diffusion routine
!
!  8-aug-02/nils: coded
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mvar+maux) :: f
!
      if (ip==1) print*,topbot,f(1,1,1,1)  !(to keep compiler quiet)
!
    end subroutine bc_ee_inflow_x
!***********************************************************************
    subroutine  bc_ee_outflow_x(f,topbot)
!
!  Dummy routine for Flux Limited Diffusion routine
!
!  8-aug-02/nils: coded
!
      character (len=3) :: topbot
      real, dimension (mx,my,mz,mvar+maux) :: f
!
      if (ip==1) print*,topbot,f(1,1,1,1)  !(to keep compiler quiet)
!
    end subroutine bc_ee_outflow_x
!***********************************************************************

endmodule Radiation
