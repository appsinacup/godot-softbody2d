# ![icon](https://raw.githubusercontent.com/Ughuuu/godot-4-softbody2d/main/addons/softbody2d/plugin_icon.png) softbody2d

Generates polygon outline, internal vertices, bones, rigidbodies and joints so you can turn a texture into a softbody2d.
Based on Polygon2d Generator.

## Introduction

This addon helps you create 2d softbodies using 2d bones and circle rigidbodies technique.
The idea is to use a Polygon2D for the main texture(this works with one texture for now).
Then, generate a polygon with inside vertices for it so it deforms nicely.
After that, create a Skeleton2D with Bone2D nodes that all follow the center Bone2D node.
After that, create for each Bone2D a matching Rigidbody2D with Circle shape and joints that tie them all togheter in a web pattern.

This tool automates that.

![Softbody2d](https://i.imgur.com/49s3PcJ.gif)

## Steps

1. Select a Polygon2D node.
2. Add a SoftBody2D script to it.
3. Click Bake Softbody

NOTE: each step can be restarted but you will lose what you are trying to generate
(eg. if you regenerate skeleton will delete old one)

## Tips


- If you make circle shapes too small, things might enter between them and ruin the phisics simulation.
- If you make everything too loose, the phisics simulation might break. Play for begining with joint damping but careful not to make it too small.
- You can also change the softbody2d_phys.tres that is used for the shapes to further customize the softbodies.
- Increase physics/common/physics_ticks_per_second to 240.
- If you make the polygon increment too big or too small, it will look triangly.

## Changelog

### Version 0.6

- Change how softbodies are generated. Use voronoi for generating polygons, then store polygons for each bone. This is used for cutting softbodies.
- There is now option to cut softbodies, making them breakable. This is done by adding breakable_rigidboy2d.gd script(you can also extend it). Still wip.

### Version 0.5

- Create just one script, SoftBody2D that you can put on a Polygon2D that generates all nodes below.

### Version 0.4

- Fix bug where if object is rotated weight generation isn't correct.

### Version 0.3

- Add more tips on how to get a good simulation
- Fix case where if root object is rotated, generation doesn't work.

### Version 0.2

- Fix bug with version 4.0 RC3.
- Add more options, make defaults more stable.
- Add more docs on how to use.

### Version 0.1

Initial Release
