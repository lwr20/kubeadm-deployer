#!/bin/bash
python -c 'import random; print "%6x.%16x" % (random.SystemRandom().getrandbits(3*8), random.SystemRandom().getrandbits(8*8))'
