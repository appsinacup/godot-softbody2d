# softbody2d

Based on Polygon2d Generator. Generates polygon outline, internal vertices, bones, rigidbodies and joints so you can turn a texture into a softbody2d.

## Introduction

This addon helps you create 2d softbodies using 2d bones and circle rigidbodies technique.
The idea is to use a Polygon2D for the main texture(this works with one texture for now).
Then, generate a polygon with inside vertices for it so it deforms nicely.
After that, create a Skeleton2D with Bone2D nodes that all follow the center Bone2D node.
After that, create for each Bone2D a matching Rigidbody2D with Circle shape and joints that tie them all togheter in a web pattern.

This tool automates that.

## Steps

1. Select a Polygon2D node.
2. Click Generate Polygon.
- Step determines at distance to create internal points from one another.
3. Click Create Skeleton2D.
4. Click Generate Rigidbodies.

NOTE: each step can be restarted but you will lose what you are trying to generate
(eg. if you regenerate skeleton will delete old one)

## Tips

- To get good results, use at most 2-3 layers of circles, so there aren't too many joints levels. Also, try to use square shapes, as those tend to perform better.

Eg:

o-o-o
|x|x|
o-o-o
|x|x|
o-o-o

Bigger shapes tend to stick and not keep their shape, unless you play a lot with the parameters. If you do use bigger shapes with a lot of circles, increase joint damping and joint stiffness.

- If you make circle shapes too small, things might enter between them and ruin the phisics simulation.
- If you make everything too loose, the phisics simulation might break. Play for begining with joint damping but careful not to make it too small.
- You can also change the softbody2d_phys.tres that is used for the shapes to further customize the softbodies.

## Changelog

### Version 0.2

- Fix bug with version 4.0 RC3.
- Add more options, make defaults more stable.
- Add more docs on how to use.

### Version 0.1

Initial Release
