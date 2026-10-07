# Basilisk pulsed jet -- MPI simulation + parallel frame rendering + video
#
#   make full                      simulate (MPI), render frames, encode video
#   make full NP=6 LEVEL=10        same, other resolution / rank count
#   make run | frames | movie      individual stages (each can be re-run alone)
#   make clean                     remove binaries
#   make full RUNDIR=/dev/shm/jet  run in RAM (copy jet.mp4 out afterwards)
#
# Needs: $BASILISK exported (path to basilisk/src), qcc in PATH, mpicc/mpirun,
# ImageMagick (convert) for PNG frames, ffmpeg for the video.

SRC     ?= atomisation.c
EXE     ?= $(SRC:.c=)
POSTSRC ?= post.c
POST    ?= $(POSTSRC:.c=)

NP      ?= 6
LEVEL   ?= 15
UEMAX   ?= 0.1
JOBS    ?= $(shell nproc)
FPS     ?= 24
MPICC   ?= mpicc
# Core binding (--bind-to core) made the run ~40% slower on this laptop: off by default
MPIRUN_FLAGS ?=

ifndef BASILISK
$(error BASILISK is not set: export BASILISK=/path/to/basilisk/src)
endif

# Flags shared by the simulation and the post-processing program
COMMON  = -O2 -Wall -disable-dimensions -grid=quadtree
GLLIBS  = -L$(BASILISK)/gl -lglutils -lfb_tiny

# Optional profiling: make TRACE=2 (changing flags requires make clean)
ifdef TRACE
TRACEFLAG = -DTRACE=$(TRACE)
endif

# Optional websocket display server: make WS=1
# (named WS on purpose: DISPLAY is already an X11 environment variable)
ifdef WS
WSFLAGS = -DDISPLAY=1 -L$(BASILISK)/wsServer -lws -lpthread
endif

RUNDIR = run-L$(LEVEL)-np$(NP)-ue$(UEMAX)

.PHONY: all full run frames movie clean clean-frames

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
	  $(CURDIR)/$(EXE) $(LEVEL) $(UEMAX) 2> log-$(LEVEL)-$(NP) > out-$(LEVEL)-$(NP)

# One serial process per dump, JOBS at a time. Frames newer than their dump are skipped.
frames: $(POST)
	@ls $(RUNDIR)/dump-[0-9][0-9][0-9][0-9] >/dev/null 2>&1 || { echo "no dump-XXXX files in $(RUNDIR): does the simulation have the 'frames' dump event?"; exit 1; }
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
	$(MAKE) run && $(MAKE) frames && $(MAKE) movie && $(MAKE) clean-frames

clean:
	rm -f $(EXE) $(POST) _$(SRC) _$(POSTSRC)

clean-frames:
	rm -f $(RUNDIR)/frame-*.png $(RUNDIR)/frame-*.log

clean-dump:
	rm -f $(RUNDIR)/dump-[0-9][0-9][0-9][0-9]