# ppmtomask
Generate a mask from a .ppm file based on pixel saturation or colour.

Read a .ppm file (P3 or P6) as named by the final parameter of the command line, and generate a mask based either on the degree of pixel saturation or on a pixel being a specific colour.

If the first parameter on the command line is -saturation then the second is assumed to be a percentage, pixels with more than this saturation (e.g. pure red or blue as distinct from medium-saturation purple) are output black with everything else white.

If the first parameter on the command line is -colour then the second etc. are assumed to be RGB triplets each expressed as six hex digits, pixels with any precisely-matched colour are output black with everything else white.

The intention of this program is to generate masks to allow coloured lines or areas that have been overlaid onto a photograph to be extracted and reused. As a specific example, a synoptic weather chart might have its front lines removed, a rainfall radar image overlaid, and the fronts replaced as the top layer.
