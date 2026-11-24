// post.c - Conforme à src/view.h pour rendu 2D (quadtree) et 3D (octree + fb_tiny)
#include "navier-stokes/centered.h"
#include "two-phase.h"
#include "tension.h"
#include "view.h"

int main (int argc, char * argv[])
{
  // 1. Restaurer le dump AVANT d'initialiser view() pour récupérer L0, X0, Y0, Z0
  restore (file = argv[1]);

#if dimension == 2
  scalar omega[];
  vorticity (u, omega);
  view (tx = -0.5);
  clear();
  draw_vof ("f");
  squares ("omega", linear = true, spread = 10);
  box ();
#else // dimension == 3
  // Fond gris très clair (bg) pour contraster avec la surface VOF et la boîte
  view (camera = "iso",
        fov = 26., tx = -0.35, ty = 0.20,
        bg = {0.95, 0.95, 0.95},
        width = 1280, height = 960);
  clear();

  // fc = couleur des facettes 3D (obligatoire avec fb_tiny pour éviter le blanc sur blanc)
  // edges = true affiche le maillage VOF sur l'interface (utile pour contrôler la résolution)
  draw_vof ("f", fc = {0.15, 0.45, 0.85}, edges = true, lw = 0.3);
  box (lc = {0.2, 0.2, 0.2}, lw = 1.);
#endif

  save (argv[2]);
}