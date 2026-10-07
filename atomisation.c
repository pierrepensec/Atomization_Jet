#include "grid/quadtree.h"
#include "navier-stokes/centered.h"
#include "two-phase.h"
#include "tension.h"
#include "tag.h"
#include "view.h"


double radius = 1./12.;
double length = 0.025;
double Re = 5800;
double SIGMA = 3e-5;

int maxlevel = 9;
double uemax = 0.1;



double u0 = 1., au = 0.05, T0 = 0.1;
scalar f0[];
u.n[left]  = dirichlet(f0[]*(u0 + au*sin (2.*pi*t/T0)));
u.t[left]  = dirichlet(0);
#if dimension > 2
u.r[left]  = dirichlet(0);
#endif
p[left]    = neumann(0);
f[left]    = f0[];

u.n[right] = neumann(0);
p[right]   = dirichlet(0);


int main (int argc, char * argv[])
{
  if (argc > 1)
    maxlevel = atoi (argv[1]);
  if (argc > 2)
    uemax = atof (argv[2]);
  init_grid (64);
  size(2);
  origin (0, -1);

  rho1 = 1. [0], rho2 = rho1/27.84;
  mu1 = 2.*u0*radius/Re*rho1, mu2 = 2.*u0*radius/Re*rho2;
  f.sigma = SIGMA;

  run();
}

event init (t = 0) {
  if (!restore (file = "restart")) {
    refine (x < 1.2*length && sq(y) + sq(z) < 2.*sq(radius) && level < maxlevel);
    fraction (f0, sq(radius) - sq(y) - sq(z));
    f0.refine = f0.prolongation = fraction_refine;
    restriction ({f0}); // for boundary conditions on levels
    foreach() {
      f[] = f0[]*(x < length);
      u.x[] = u0*f[];
    }
  }
}

event logfile (i++) {
  if (i == 0)
    fprintf (stderr,
	     "t dt mgp.i mgpf.i mgu.i grid->tn perf.t perf.speed\n");
  fprintf (stderr, "%g %g %d %d %d %ld %g %g\n", 
	   t, dt, mgp.i, mgpf.i, mgu.i,
	   grid->tn, perf.t, perf.speed);
}

// event movie (t += 2e-2)
// {
// #if dimension == 2
//   scalar omega[];
//   vorticity (u, omega);
//   view (tx = -0.5,cache=10);
//   clear();
//   draw_vof ("f");
//   squares ("omega", linear = true, spread = 10);
//   box ();
// #else // 3D
//   scalar pid[];
//   foreach()
//     pid[] = fmod(pid()*(npe() + 37), npe());
//   view (camera = "iso",
// 	fov = 14.5, tx = -0.418, ty = 0.288,
// 	width = 1600, height = 1200);
//   clear();
//   draw_vof ("f");
// #endif // 3D
//   save ("movie.mp4");
// }


event adapt (i++) {
  adapt_wavelet ({f,u}, {0.01,uemax,uemax,uemax}, maxlevel);
}

event snapshot (t = 0.0; t += 2e-2; t <= 3.5) {
  char name[80];
  sprintf (name, "dump-%04d", (int) round (t/e-2));
  scalar pid[];
  foreach()
    pid[] = fmod(pid()*(npe() + 37), npe());
  dump (name);
}