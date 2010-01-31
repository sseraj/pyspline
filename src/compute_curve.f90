subroutine compute_curve(s,X,t,k,n,nctl,ndim,coef,niter,tol,rms)

  !***DESCRIPTION
  !
  !     Written by Gaetan Kenway
  !
  !     Abstract: compute_curve is the main function for the
  !               generation fo B-spline curves It does both
  !               interpolating and LMS fits, as well as Hoschek's 
  !               Parameter Correction.
  !
  !     Description of Arguments
  !     Input
  !     s       - Real, Vector of s coordinates, length n
  !     X       - Real, Array of X values to fit, Size (n,ndim)
  !     t       - Real,Knot vector. Length nctl+k
  !     k       - Integer,order of spline
  !     nctl    - Integer,Number of control points
  !     ndim    - Integer, spatial dimension of curve
  !     niter   - Integer, number of hoscek para-correction iterations
  !     tol     - Integer, relative tolerance for convergence
  !
  !     Ouput coef - Real,Array of B-spline coefficients. Size (nctl,ndim)

  use lms_jacobian
  use  lsqrModule,        only : LSQR
  use  lsqrCheckModule,   only : Acheck, xcheck

  implicit none
  
  ! Input
  integer         , intent(in)          :: k,nctl,ndim,n
  double precision, intent(in)          :: X(n,ndim)
  double precision, intent(inout)       :: s(n)
  double precision, intent(in)       :: t(nctl+k)
  integer         , intent(in)          :: niter
  double precision, intent(in)          :: tol

  ! Output
  double precision, intent(inout)       :: coef(nctl,ndim)
  double precision, intent(out)         :: rms
  ! Working
  integer                               :: i,idim,iter
  double precision                      :: weight
  double precision                      :: length,res,norm,tot,val(ndim)
  integer                               :: istop,itn
  double precision                      :: Anorm,Acond,rnorm, Arnorm,xnorm
  ! Functions called
  double precision                      :: poly_length,floor,compute_rms_curve

  !Initialization
  length = poly_length(X,n,ndim)  
  call setup_jacobian(n,nctl,k)
  call curve_jacobian_linear(t,k,s,n,nctl)

  do iter=1,niter
     ! Solve
     idim = 1
     do idim=1,ndim
        call LSQR( n, Nctl, Aprod1, Aprod2,X(:,idim),0.0, .False., &
             coef(:,idim), vals, 1e-12, 1e-12, 1e8, Nctl*4,0,&
             istop, itn, Anorm, Acond, rnorm, Arnorm, xnorm )
     end do
     call curve_para_corr(t,k,s,coef,nctl,ndim,length,n,X)
     rms = compute_rms_curve(t,k,s,coef,nctl,ndim,length,n,X)
     call curve_jacobian_linear(t,k,s,n,nctl)
     ! Do convergence Check to break early
  end do
 
  call kill_jacobian()

end subroutine compute_curve

subroutine curve_jacobian_linear(t,k,s,n,nctl)
  use lms_jacobian

  implicit none
  ! Input
  double precision     ,intent(in)      :: t(nctl+k)
  double precision     ,intent(in)      :: s(n)
  integer              ,intent(in)      :: k,nctl,n
  ! Output -> in lms_jacobian module

  double precision                      :: vnikx(k),work(2*k)
  integer                               :: i,j,counter
  integer                               :: ilo,ileft,mflag,iwork
  
  ilo = 1
  counter = 1
  do i=1,n
     call intrv(t,nctl+k,s(i),ilo,ileft,mflag)
     if (mflag == 0) then
        call bspvn(t,k,k,1,s(i),ileft,vnikx,work,iwork)
     else if (mflag == 1) then
        ileft = nctl
        vnikx(:) = 0.0
        vnikx(k) = 1.0
     end if

     row_ptr(i) = counter
     do j=1,k
        col_ind(counter) = ileft-k+j
        vals(counter) =vnikx(j)
        counter = counter + 1
     end do

  end do
  row_ptr(n+1) = counter
end subroutine curve_jacobian_linear

function poly_length(X,n,ndim)
  ! Compute the length of the spatial polygon
  implicit none
  !Input
  double precision ,intent(in)    :: X(n,ndim)
  integer          ,intent(in)    :: n,ndim
  integer                         :: i,idim
  double precision                :: dist
  double precision poly_length
  poly_length = 0.0
  do i=1,n-1
     dist = 0.0
     do idim=1,ndim
        dist = dist + (X(i,idim)-X(i+1,idim))**2
     end do
     poly_length = poly_length + sqrt(dist)
  end do
  
end function poly_length

subroutine curve_para_corr(t,k,s,coef,nctl,ndim,length,n,X)

  ! Do Hoschek parameter correction
  implicit none
  ! Input/Output
  double precision  ,intent(in)      :: t(k+nctl)
  double precision  ,intent(inout)   :: s(n)
  double precision  ,intent(in)      :: coef(nctl,ndim)
  integer           ,intent(in)      :: k,nctl,ndim,n
  double precision  ,intent(in)      :: X(n,ndim)
  double precision  ,intent(in)      :: length
  ! Working
  integer                            :: i,j,max_inner_iter
  double precision                   :: D(ndim),D2(ndim)
  double precision                   :: val(ndim),deriv(ndim)
  double precision                   :: c,s_tilde,norm

  max_inner_iter = 10
  do i=2,n-1
     call eval_curve(s(i),t,k,coef,nctl,ndim,val)
     call eval_curve_deriv(s(i),t,k,coef,nctl,ndim,deriv)
          
     D = X(i,:)-val
     c = dot_product(D,deriv)/norm(deriv,ndim)

     inner_loop: do j=1,max_inner_iter

        s_tilde = s(i)+ c*(t(nctl+k)-t(1))/length
        call eval_curve(s_tilde,t,k,coef,nctl,ndim,val)
        D2 = X(i,:)-val
        if (norm(D,ndim) .ge. norm(D2,ndim)) then
           s(i) = s_tilde
           exit inner_loop
        else
           c = c*0.5
        end if
     end do inner_loop
  end do

end subroutine curve_para_corr

function norm(X,n)
  ! Compute the L2 nomr of X
  implicit none
  double precision       :: X(n)
  double precision       :: norm
  integer                :: i,n
  norm = 0.0
  do i=1,n
     norm = norm + X(i)**2
  end do
  norm = sqrt(norm)
end function norm

function compute_rms_curve(t,k,s,coef,nctl,ndim,length,n,X)
  ! Compute the rms
  implicit none
  ! Input/Output
  double precision  ,intent(in)      :: t(k+nctl)
  double precision  ,intent(in)      :: s(n)
  double precision  ,intent(in)      :: coef(nctl,ndim)
  integer           ,intent(in)      :: k,nctl,ndim,n
  double precision  ,intent(in)      :: X(n,ndim)
  double precision  ,intent(in)      :: length
  double precision                   :: compute_rms_curve 

  ! Working
  integer                            :: i,idim
  double precision                   :: val(ndim),D(ndim)
  
  compute_rms_curve = 0.0
  do i=1,n
     call eval_curve(s(i),t,k,coef,nctl,ndim,val)
     D = val-X(i,:)
     do idim=1,ndim
        compute_rms_curve = compute_rms_curve + D(idim)**2
     end do
  end do
  compute_rms_curve = sqrt(compute_rms_curve/n)
end function compute_rms_curve
