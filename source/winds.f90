! ***********************************************************************
SUBROUTINE WINDS(nG,EtaOK)
! =======================================================================
! This subroutine takes care of the interface between radiatively driven
! winds and radiative transfer.  It is entered
! after a radiative transfer calculation with given eta.
! This sub caclulates the reddening profile phi and passes it to the dynamics
! module, which returns the velocity and density profiles corresponding
! to the given phi. Convergence is achived when the eta returned from
! the dynamics calculation is the same as that used to produce phi.
!
! Notations follow EI01 (MNRAS 327, 403)
! =======================================================================
  use common
  use interfaces
  implicit none

  integer nG, EtaOK, iY, iL, err
  double precision ETAold(npY),acceta, resaux, faux(npL), Qfid, phi1,   &
          localP, eps_loc, GammaMax, wScale, uacc, reddn(npY), w(npY)

! the parameter ver determines the version of the velocity formal solution
! 1 for linear, 2 quadratic.  it is specified in input and carried in /dyn/
! the quadratic solution is from equation d1 in ei01. the linear is
! obtained similarly from the differential equation 24 by using dw^2 = 2wdw
! and dividing through by 2w
! -----------------------------------------------------------------------
      IF (iX.GE.1) THEN
         write(18,*)' Doing Dynamics'
         IF (ver.EQ.1) THEN
           write(18,*)' Linear version of velocity formal solution'
         ELSEIF (ver.EQ.2) THEN
           write(18,*)' Quadratic version of velocity formal solution'
         ELSE
           write(12,*)' **************************** '
           write(12,'(a,i3)')'  Illegal Input ver = ', ver
           write(12,*)'     ver must be 1 or 2!      '
           write(12,*)'       PROGRAM STOPPED        '
           write(12,*)' **************************** '
           stop
         END IF
      END IF
      IF(iVerb.EQ.2) write(*,*)' Doing Dynamics'
!     so far it works for nG=1 only:
      IF (nG.GT.1) THEN
        write(12,*)' **************************** '
        write(12,*)' Change dynamics sub to nG>1! '
        write(12,*)'       PROGRAM STOPPED        '
        write(12,*)' **************************** '
        stop
      END IF
! -----------------------------------------------------------------------
!     assign input parameters to local variables
      GammaMax = ptr(1)
      eps_loc = pow
!     accuracy for velocity convergence same as for Utot:
      uacc = accConv
!     extinction efficiency at the fiducial wavelength
      Qfid = SigExfid/aveA
!     calculate Qstar and the scale factor of w:
      DO iL = 1, nL
         Faux(iL) = (SigmaA(1,iL)+SigmaS(1,iL))*ftot(iL,1)/lambda(iL)
      END DO
      CALL Simpson(npL,1,nL,lambda,Faux,resaux)
!
!     Qstar is from EI01 equation 4, wScale is from equation 29
!
      Qstar = resaux / aveA
      wScale = TAUfid/Qfid
!
! -----------------------------------------------------------------------
!     Here's the eta that was used in the radiative transfer
      DO iY = 1, nY
        ETAold(iY) = ETAdiscr(iY)
      END DO
!     and here's the resulting reddening profile
      DO iY = 1, nY
        DO iL = 1, nL
          Faux(iL) = (SigmaA(1,iL)+SigmaS(1,iL))*ftot(iL,iY)/lambda(iL)
          print*,'still single grain L7370'
          stop
        END DO
        CALL Simpson(npL,1,nL,lambda,Faux,resaux)
        if (iY.eq.1)    phi1 = resaux
        reddn(iY) = resaux / phi1  ! eq.(3);reddn(iY)=phi_loc in Dynamics
      END DO
!     Now Find new ETA
      err = 0
      CALL DYNAMICS(eps_loc, GammaMax, wScale, reddn, w, vrat, gmax,  &
                     localP, ETAdiscr, Y, nY, nG, uacc, err, iX, ver)
!!** Prdw=P is stored in common /dyn/, needed in Analysis [MN]
     Prdw = localP

!     and check convergence (ptr(2) is specified in INPUT)
      accETA = ptr(2) * accuracy
      CALL ChkConv(accETA,ETAold,ETAdiscr,EtaOK)
      IF (iX.GE.1) THEN
        write(18,'(2(a,1pe10.3))') '  P = ', localP, '  gmax = ', gmax
        write(18,*) '     Y    ugas(new)   tauF      ETAold    ETAnew    ratio'
        DO iY = 1, nY
!**************************************
!        for output compatibility; we can do away with qF and tauF, which
!        have only nostalgic reasons.  EI01 never uses them
!        ugas is in common /dyn/ and used in Analysis [MN]
          ugas(iY) = Qstar*w(iY)
          qF(iY)   = (Qstar/Qfid)*reddn(iY)
          Faux(iY) = qF(iY)*ETAdiscr(iY)
          CALL SIMPSON(npY,1,iY,Y,Faux,resaux)
          tauFdyn(iY) = TAUfid*resaux
!**************************************
          accETA = ETAold(iY) / ETAdiscr(iY)
          write(18,'(1p,6e10.3)')Y(iY), ugas(iY), tauFdyn(iY),   &
                                 ETAold(iY), ETAdiscr(iY),accETA
        END DO
        IF (EtaOK.EQ.1) THEN
          write(18,*)' Convergence on Eta achieved'
        ELSE
          write(18,*)' Convergence on Eta not achieved.'
          write(18,*)' Going to the next iteration.'
        END IF
      END IF
!     save Y to Yprev and nY to nYprev
      DO iY = 1, nY
         Yprev(iY) = Y(iY)
      END DO
      nYprev = nY
! -----------------------------------------------------------------------
      RETURN
      END subroutine Winds
! ***********************************************************************

! ***********************************************************************
      SUBROUTINE DYNAMICS(eps_loc, f, uScale, phi_loc, u, zeta, gmax,  &
	                     P, eta, Y, nY, nG, acc, err, iX, ver)
! =======================================================================
! Calculates the velocity structure of a radiatively driven
! wind given the reddening profile phi.  It returns the
! profiles w, eta and zeta, and the wind parameters P and gmax.
!
! This subroutine calculates the initial guess and controlls the
! convergence of the iterative procedure, with CalcVel actually
! calculating a new velocity profile from the previous one.
! Convergence is checked both for u(y) (= w(y)) and its derivative eta(y)
! because eta is crucial for the radiative transfer.
! *** This version works for single size grains only ***
!
! Implementing equations from EI01 (MNRAS 327, 403)
!=======================================================================

  implicit none
  integer npY, npP, npX, npL, npG, npR
  include '../userpar.inc'
  integer nG, nY, iY, itr, ETAconv, uconv, err, iX, itmax, ver
  double precision eta(npY), etaold(npY), u(npY), uold(npY),  &
       phi_loc(npY), zeta(npG,npY), Y(npY), eps_loc, f, acc, gmax, &
       uScale, N, P, wf, k, e1
  data   itMax/100/, k/0.4/
!  we may wish to control itMax and k as input parameters
! -----------------------------------------------------------------------
!     for information: phi_loc(nY) = reddn(nY)     [MN]
!                    zeta(npG,npY) = vrat(npG,npY)

!     Initial approximation for u(y) from EI01, eq C6
!     wf is from eq. 29 with epsilon correction (eq. C8)
      wf = (1.0d+00/(1.0d+00 - eps_loc))*phi_loc(nY)*uScale
!     add a correction for the finite outer radius so that wf = u(nY):
      e1 = 1.0d+00 - eps_loc**(1.0d+00/k)
      wf = wf/(1.0d+00 - e1/Y(nY))**k
!     and now calculate all u from eq. C6
      DO iY = 1, nY
         uold(iY) = wf*(1.0d+00 - e1/Y(iY))**k
!        initial eta is irrelevant; might as well use
!        the one passed from radiative transfer:
         ETAold(iY) = eta(iY)
      END DO

!     ITERATIONS until u and eta converge within acc
      DO itr = 1, itMax
         Call CalcVel(eps_loc,f,uScale,phi_loc,uold,u,zeta,gmax,Y,nY,ver)
         CALL CalcETA(u, zeta, eta, N, Y, nY)
!        here N=EtaINT found in CalcEta
         P = dsqrt(uScale/N)       !eq.(46) in IE'01
!        check convergence of u and Eta
         CALL ChkConv(acc,uold,u,uconv)
         CALL ChkConv(acc,ETAold,eta,ETAconv)
!        convergence required for both u(y) and ETA(y)
         err = 1 - ETAconv * uconv
         IF (err.NE.0) THEN
!           did not converge, repeat the exercise...
            DO iY =1, nY
              uold(iY) = u(iY)
              ETAold(iY) = eta(iY)
            END DO
         ELSE
!          we're done:
           IF (iX.GE.1) write(18,'(a35,i3)')' Number of iterations to converge:',itr
           RETURN
         END IF
      END DO
! -----------------------------------------------------------------------
  return
end subroutine Dynamics
!***********************************************************************


! ***********************************************************************
      SUBROUTINE CalcVel(eps_loc, f, ws, phi_loc, wold, w, zeta, gmax,Y, nY, ver)
! =======================================================================
! Calculates the scaled gas velocity w(y) from wold(y), the previous
! velocity profile, and the given reddening profile phi
! The calculation follows the formal solution in Appendix D
! ver = 1 triggers the linear version, 2 the quadratic (eq. D1)
! All symbols are as defined there, ws = tauV/QV and P2 = P^2
! =======================================================================
      IMPLICIT none
      INTEGER npY, npP, npX, npL, npG, npR
      INCLUDE '../userpar.inc'
      INTEGER ver, nY, iY
      DOUBLE PRECISION eps_loc, f, wold(npY), w(npY), phi_loc(npY), &
           zeta(npG,npY), Y(npY), z(npY), zz(npY), gmax, g,        &
           ws, N, P2, ww1, aux, F1(npY), F2(npY)
! -----------------------------------------------------------------------
!     first get the drift profile zeta
      CALL CalcDrift(phi_loc, wold, zeta, nY)
!     then the normalization N (= EtaINT; eq D3)
      DO iY = 1, nY
        F1(iY) = zeta(1,iY)/(wold(iY)*Y(iY)*Y(iY))
      END DO
      CALL SIMPSON(npY,1,nY,Y, F1, N)
!     and finally P (eq. D3):
      P2 = 2.0D+00*ws/N
!     Now the two versions diverge:
      IF (ver.eq.2) THEN
!        Quadratic version (eq. D1):
!         Get the profile z = integral(zeta*phi/y^2) and gmax
!         (= Gamma_min), the maximum gravitational correction
!         as defined in eqs D4 and D5:
          F1(1) = 0.0D+00
          z(1)  = 0.0D+00
          gmax  = 1.0D+00/zeta(1,1)
          DO iY = 2, nY
             F1(iY) = zeta(1,iY)*phi_loc(iY)/(Y(iY)*Y(iY))
             CALL SIMPSON(npY,1,iY,Y, F1, z(iY))
             aux = (1.0D+00 - 1.0D+00/Y(iY))/z(iY)
             if (aux.gt.gmax) gmax = aux
          END DO
          g = f/gmax
!         All ready.  Calculate the new w1 (ww1 = w1^2):
          aux  = eps_loc*eps_loc
          ww1  =(aux/(1.0D+00-aux))*P2*(z(nY)-g*(1.0D+00-1.0D+00/Y(nY)))
          w(1) = dsqrt(ww1)
!         and now the rest of the profile:
          DO iY = 2, nY
             aux   = ww1 + P2*(z(iY)-g*(1.0D+00-1.0D+00/Y(iY)))
             w(iY) = dsqrt(aux)
          END DO
      ELSE
!        Linear version.
!         obtained from the differential equation 24
!         by using dw^2 = 2wdw and dividing through by 2w
!         Now we need the profiles z = integral(zeta*phi/w*y^2),
!         zz = integral(1/w*y^2) and then gmax = max(zz/z)
          F1(1) = 0.0D+00
          F2(1) = 0.0D+00
          z(1)  = 0.0D+00
          zz(1) = 0.0D+00
          gmax  = 1./zeta(1,1)
          DO iY = 2, nY
             F2(iY) = 1.0D+00/(wold(iY)*Y(iY)*Y(iY))
             F1(iY) = F2(iY)*zeta(1,iY)*phi_loc(iY)
             CALL SIMPSON(npY,1,iY,Y, F1, z(iY))
             CALL SIMPSON(npY,1,iY,Y, F2, zz(iY))
             aux = zz(iY)/z(iY)
             if (aux.gt.gmax) gmax = aux
          END DO
          g = f/gmax
!         All ready.  Calculate the new w1:
          w(1)  = (eps_loc/(1.0D+00-eps_loc))*0.5D+00*P2*(z(nY) - g*zz(nY))
!         and now the rest of the profile:
          DO iY = 2, nY
             w(iY) = w(1) + 0.5D+00*P2*(z(iY) - g*zz(iY))
          END DO
      END IF
! -----------------------------------------------------------------------
      RETURN
      END SUBROUTINE CalcVel
! ***********************************************************************


! ***********************************************************************
      SUBROUTINE CalcETA(w, zeta, Eta, EtaINT, Y, nY)
! =======================================================================
! Calculates the dimensionless density profile ETA(y) from EI eq. 25 given
! the velocity profile w(y) and its corresponding drift zeta(y)
! =======================================================================
      IMPLICIT none
      INTEGER npY, npP, npX, npL, npG, npR
      INCLUDE '../userpar.inc'
      INTEGER iY, nY
      DOUBLE PRECISION w(npY), Eta(npY), zeta(npG,npY), Y(npY), EtaINT
! ======================================================================
      DO iY = 1, nY
        Eta(iY) = zeta(1,iY)/(w(iY)*Y(iY)*Y(iY))
      END DO
!     now normalize eta:
      CALL SIMPSON(npY,1,nY,Y,Eta,EtaINT)
      DO iY = 1, nY
        Eta(iY) = Eta(iY)/EtaINT
      END DO
! -----------------------------------------------------------------------
      RETURN
      END
! ***********************************************************************

! ***********************************************************************
      SUBROUTINE CalcDrift(phi_loc,w,zeta,nY)
! =======================================================================
! Calculates the drift profile zeta from EI01 eq. 24
! without the correction for sub-sonic drift (theta = 0).
! =======================================================================
      IMPLICIT none
      INTEGER npY, npP, npX, npL, npG, npR
      INCLUDE '../userpar.inc'
      INTEGER nY, iY
      DOUBLE PRECISION phi_loc(npY), w(npY), zeta(npG,npY)
! -----------------------------------------------------------------------
      DO iY = 1, nY
         zeta(1,iY) = 1.0D+00 / (1.0D+00 + dsqrt(phi_loc(iY)/w(iY)))
      END DO
! -----------------------------------------------------------------------
      RETURN
      END SUBROUTINE CalcDrift
! ***********************************************************************
