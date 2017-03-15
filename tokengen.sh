#!/bin/bash
python -c 'import random; print "{:06x}.{:016x}".format(random.SystemRandom().getrandbits(3*8), random.SystemRandom().getrandbits(8*8))'
