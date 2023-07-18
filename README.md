# ![icon](https://raw.githubusercontent.com/Ughuuu/godot-4-softbody2d/main/addons/softbody2d/plugin_icon.png) SoftBody2D

# Introduction

![Example](docs/example.png)

Create 2D SoftBodies from a Texture.

1. Create a SoftBody2D node, add a texture to it.
2. Then click bake.

This will create multiple rigidbodies for each region of the object.

# How to install

Download the sourcecode and move only the addons folder it contains into your project folder addons folder. 

# Features

The softbody is constructed out of multiple pieces. The texture is first split into multiple polygons from a source image, the rigidbodies are created and connected with joints.

## Polygon

* Bake from inspector
* Vertex Interval: This sets how far apart two rigidbodies will be.
* Voronoi Interval: This sets how much will the rigidbodies move relative to their original center.
* Polygon Offset: Do manual adjustments if bodies are not generated how you want them.
* Min Area: If the resulting area of a body is too small, merge it with a nearby area.

## Image

* Margin Pixels: Shrink or Expand the original image
* Texture Epsilon: Get more or less points on the polygon outline
* Min Alpha: Minimum alpha needed to consider texture part of softbody.

## Joint

* Look at center: Wether the resulting bone (which transforms the texture based on rigidbody position) should look at center bone (if you have breakable bodies enabled, then the center bone will change) or to look at the middle most adjacent bone.
* Joint Type: This plugin supports Pin or Spring joint
* Bias, Disable Collision, Stiffness, Damping, Softness: Joint specific properties

## Rigidbody

* Soft on inside: Make the inside bodies have less mass.
* Script: Add a custom script to be added to the rigidbody. Eg. `breakable_rigidbody2d.gd` script
* Radius, collision layer, collision mask, mass, pickable, lock rotation, material override: Rigidbody specific properties.

# How it works

## Polygon

1. Creates edge vertices from texture.

2. Creates multiple voronoi regions with roughly same total size as the edge vertices AABB.

![Voronoi Object](docs/voronoi_object.png)

3. Delete the voronoi regions not inside the polygon.

![Voronoi Cut](docs/voronoi_cut.png)

4. Assigns these polygons to the `Polygon2D.polygon` and `Polygon2D.polygons`.

## Skeleton2D

1. Creates a `Skeleton2D` child.
2. Creates a set of `Bone2D`` nodes of the `Skeleton2D`, each having a voronoi region and assign correct weights to them.

## RigidBody2D

1. Creates a set of `RigidBody2D` nodes, one for each voronoi region.
2. Creates for each `Bone2D` a `Rigidody2D` with a `CollisionShape2D` (with a `CircleShape2D` shape) child, a `RemoteTransform2D` child that targets the `Bone2D` position, and either `DampedSprintJoint2D` or `PinJoint2D` children that connects each other neighbour nodes.


![Soft Body](docs/softbody.png)

## For breakable softbodies

If you assign to each rigidbody a `breakable_rigidbody2d.gd` script(done in inspector at SoftBody2D/Rigidbody/Rigidbody Script)

1. When the joint length is too big, the joints breaks. Then, the script `breakable_rigidbody2d.gd` calls on SoftBody2D script `remove_joint` function, which changes weights for both bones to no longer have weights in other voronoi region.

That's it. Because of the way the bones weights are built, they have overlapping points that just need to be removed when joint is broken. Easy!

# Credits

Uses parts of code from (godot-chunked-voronoi-generator)[https://github.com/arcanewright/godot-chunked-voronoi-generator]
