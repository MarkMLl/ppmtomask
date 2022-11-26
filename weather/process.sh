#!/bin/bash

echo -n 'Converting analysis .png... '
pngtopam atl_analysis.png > atl.ppm && echo 'OK'

echo -n 'Converting satellite .jpeg... '
jpegtopnm sat_eur_irrad.jpeg | pnmquant 256 > sat.ppm && echo 'OK'

echo -n 'Shrinking satellite image... '
pamstretch-gen 0.69 sat.ppm > scaled_sat.ppm && echo 'OK'

echo -n 'Pad satellite image... '
pnmpad -left 551 -width 1140 -height 635 scaled_sat.ppm > padded_sat.ppm && echo 'OK'

# At this point, the analysis and satellite images should be the same size.

COLD='0026c1'
WARM='c72500'
OCCLUDED='b327b3'

# I might have seen c72700 there. There's a possibility that the originators
# might fiddle the precise colours to discourage people from trying to scrape
# the image. It's what I'd do...

# echo -n 'Generate a pair of fronts masks for analysis image... '
# ppmtomask -colours $COLD $WARM $OCCLUDED atl.ppm > fronts_mask.ppm && echo -n 'OK... '
# ppmtomask -not -colours $COLD $WARM $OCCLUDED atl.ppm > fronts_mask_not.ppm && echo 'OK'

SATURATED='68.0%'

echo -n 'Generate a pair of precipitation masks for satellite image... '
ppmtomask -saturation $SATURATED padded_sat.ppm > precipitation_mask.ppm && echo -n 'OK... '
ppmtomask -not -saturation $SATURATED padded_sat.ppm > precipitation_mask_not.ppm && echo 'OK'

echo -n 'Isolate precipitation... '
pamarith -multiply padded_sat.ppm precipitation_mask_not.ppm > precipitation_only.ppm && echo 'OK'

echo -n 'Punch precipitation out of analysis... '
pamarith -multiply atl.ppm precipitation_mask.ppm > atl_masked_precipitation.ppm && echo 'OK'

echo -n 'Add precipitation to analysis... '
pamarith -add atl_masked_precipitation.ppm precipitation_only.ppm > atl_with_precipitation.ppm && echo 'OK'

echo -n 'Converting to .png file...'
pnmtopng atl_with_precipitation.ppm > atl_with_precipitation.png && echo 'OK'

echo -n 'Tidying up... '
rm *_*ppm sat.ppm atl.ppm && echo 'OK'

echo 'Done'

