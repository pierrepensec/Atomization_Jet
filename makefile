# Basilisk pulsed jet (2D & 3D Manifold Death) -- MPI simulation + parallel frames + video
#
#   make full-2d LEVEL=9 NP=3
#   make full-3d LEVEL=8 NP=4 HC=0.015625
#   make full SRC=atomisation_3D_MD.c LEVEL=8 NP=4 UEMAX=0.1 HC=0.015625
#   make run | frames | movie SRC=...
#   make clean

SRC     ?= simulation.c
EXE     ?= $(SRC:.c=)
POSTSRC ?= post.c

NP      ?= 3
LEVEL   ?= 9
UEMAX   ?= 0.1
HC      ?= 0.015625
JOBS    ?= $(shell nproc)
FPS     ?= 24
MPICC   ?= mpicc
# Core binding (--bind-to core) made the run ~40% slower on this laptop: off by default
MPIRUN_FLAGS ?=

ifndef BASILISK
$(error BASILISK is not set: export BASILISK=/path/to/basilisk/src)
endif

# Bascule automatique 2D (quadtree) / 3D Manifold Death (octree) selon le fichier source
ifeq ($(SRC),atomisation_3D_MD.c)
  GRID     ?= octree
  SIM_ARGS ?= $(LEVEL) $(UEMAX) $(HC)
  RUNDIR   ?= 3D-run-L$(LEVEL)-np$(NP)-ue$(UEMAX)-HC$(HC)
else
  GRID     ?= quadtree
  SIM_ARGS ?= $(LEVEL) $(UEMAX)
  RUNDIR   ?= 2D-run-L$(LEVEL)-np$(NP)-ue$(UEMAX)
endif

# Binaire de rendu distinct selon la dimension pour restaurer correctement les dumps 2D ou 3D
POST    ?= $(POSTSRC:.c=)_$(GRID)

# Flags partagés par la simulation et le post-traitement
COMMON  = -O2 -Wall -disable-dimensions -grid=$(GRID)
GLLIBS  = -L$(BASILISK)/gl -lglutils -lfb_tiny -lgsl -lgslcblas

# Optional profiling: make TRACE=2 (changing flags requires make clean)
ifdef TRACE
TRACEFLAG = -DTRACE=$(TRACE)
endif

# Optional websocket display server: make WS=1
ifdef WS
WSFLAGS = -DDISPLAY=1 -L$(BASILISK)/wsServer -lws -lpthread
endif

.PHONY: all full full-2d full-3d run frames movie clean clean-frames clean-dump

all: $(EXE) $(POST)

# MPI simulation (no -fopenmp: one process per core)
$(EXE): $(SRC)
	CC99='$(MPICC) -std=c99 -D_DEFAULT_SOURCE' qcc $(COMMON) -D_MPI=1 \
	  $(TRACEFLAG) $(SRC) -o $(EXE) $(GLLIBS) $(WSFLAGS) -lm

# Serial post-processing program (restores a dump, draws one frame)
$(POST): $(POSTSRC)
	qcc $(COMMON) $(POSTSRC) -o $(POST) $(GLLIBS) -lm

run: $(EXE)
	mkdir -p $(RUNDIR)
	cd $(RUNDIR) && OMP_NUM_THREADS=1 mpirun $(MPIRUN_FLAGS) -np $(NP) \
	  $(CURDIR)/$(EXE) $(SIM_ARGS) 2> log-$(LEVEL)-$(NP) > out-$(LEVEL)-$(NP)

# One serial process per dump, JOBS at a time. Frames newer than their dump are skipped.
frames: $(POST)
	@ls $(RUNDIR)/dump-[0-9][0-9][0-9][0-9] >/dev/null 2>&1 || { echo "no dump-XXXX files in $(RUNDIR): does the simulation have the 'snapshot' dump event?"; exit 1; }
	@command -v convert >/dev/null || \
	  echo "warning: ImageMagick 'convert' not found, frames may fall back to raw PPM"
	cd $(RUNDIR) && ls dump-[0-9][0-9][0-9][0-9] | sed 's/^dump-//' | \
	  xargs -P $(JOBS) -I{} sh -c \
	  'test frame-{}.png -nt dump-{} || $(CURDIR)/$(POST) dump-{} frame-{}.png 2> frame-{}.log'
	@n=`ls $(RUNDIR)/frame-*.png 2>/dev/null | wc -l`; \
	  nd=`ls $(RUNDIR)/dump-[0-9][0-9][0-9][0-9] | wc -l`; \
	  if [ $$n -eq 0 ]; then echo "no PNG frames produced: see $(RUNDIR)/frame-*.log (and look for frame-*.png.ppm if convert is missing)"; exit 1; fi; \
	  if [ $$n -ne $$nd ]; then echo "only $$n frames for $$nd dumps: read the frame-*.log of the missing ones"; exit 1; fi; \
	  echo "frames: $$n PNG files in $(RUNDIR)"

movie:
	@command -v ffmpeg >/dev/null || { echo "ffmpeg not found"; exit 1; }
	@idx() { sed 's/.*frame-0*\([0-9][0-9]*\)\.png/\1/'; }; \
	  first=`ls $(RUNDIR)/frame-*.png | head -1 | idx`; \
	  last=`ls $(RUNDIR)/frame-*.png | tail -1 | idx`; \
	  n=`ls $(RUNDIR)/frame-*.png | wc -l`; \
	  if [ $$n -ne $$((last - first + 1)) ]; then echo "warning: gaps in the frame sequence, ffmpeg will stop at the first gap"; fi; \
	  echo "encoding frames $$first to $$last"; \
	  ffmpeg -y -framerate $(FPS) -start_number $$first -i $(RUNDIR)/frame-%04d.png \
	    -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -pix_fmt yuv420p $(RUNDIR)/jet.mp4

# Sequential on purpose (safe with make -j)
full:
	$(MAKE) SRC=$(SRC) run && $(MAKE) SRC=$(SRC) frames && $(MAKE) SRC=$(SRC) movie && $(MAKE) SRC=$(SRC) clean-frames

# Raccourcis directs 2D et 3D
full-2d:
	$(MAKE) SRC=simulation.c full

full-3d:
	$(MAKE) SRC=atomisation_3D_MD.c full

clean:
	rm -f simulation atomisation_3D_MD $(EXE) post_quadtree post_octree _*.c

clean-frames:
	rm -f $(RUNDIR)/frame-*.png $(RUNDIR)/frame-*.log

clean-dump:
	rm -f $(RUNDIR)/dump-[0-9][0-9][0-9][0-9]