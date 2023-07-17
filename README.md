# ![icon](https://raw.githubusercontent.com/Ughuuu/godot-4-softbody2d/main/addons/softbody2d/plugin_icon.png) softbody2d

## Introduction

Create 2D SoftBodies from a Texture.

1. Create a Polygon2D node, add a texture to it.
2. Then add a SoftBody2D script. Then click bake.

This will create multiple rigidbodies for each region of the object.

If you want Breakable Softbody2D add RigidbodyScript field to `breakable_rigidbody2d.gd`(done in inspector at SoftBody2D/Rigidbody/Rigidbody Script)
, which you can also extend.

## Features

* Non-Breakable SoftBody
* Breakable SoftBody
* Pin Joint
* Groove Joint
* Configure Polygon Vertex Interval
* Two Types of Joints supported(pin and groovy) to create different effects.


## How non breakable softbodies work

1. Creates a huge voronoi diagram:

![Voronoi Diagram](docs/voronoi.png)

This way we have a fairly random distribution of points and we know where each region is separated

![Voronoi Polygon 1](docs/voronoi_poly1.png)

![Voronoi Polygon 2](docs/voronoi_poly2.png)

2. Assigns it to the `Polygon2D` node as polygons that are inside initial texture:

![Voronoi Polygon 2](docs/poly.png)


3. Create a skeleton with `Bone2D` nodes for each voronoi region that is inside the polygon.

![Voronoi Skeleton](docs/skeleton.png)

![Voronoi Skeleton 2](docs/skeleton-2.png)

4. Assign to the `Bone2D` weights with all points of that region, and also all overlapping points from neighbouring regions. Also notes on each bone what points it contained initially from voronoi region.

![Voronoi Polygon 2](docs/bones.png)

![Bone Metadata](docs/bone_metadata.png)

5. Set direction of each `Bone2D` to follow the middle of each neighbouring bones. This is done by `look_at_center_2d.gd` script. This one follows all neighbour bones. These are assigned when baking.

6. Creates for each bone a `Rigidbody2D` with a `CollisionShape2D`(with `Circle` of radius specified in inspector) child, a `RemoteTransform2D` child that targets thte `Bone2D` position, and either `DampedSprintJoint2D` or `PinJoint2D` children that connects each other neighbour nodes(the joint type is configurable from inspector).

![Rigidbodies](docs/rigidbodies.png)

## For breakable softbodies

If you assign to each rigidbody a `breakable_rigidbody2d.gd` script(done in inspector at SoftBody2D/Rigidbody/Rigidbody Script)

1. When the joint length is too big, the joints breaks. Then, the script `breakable_rigidbody2d.gd` calls on SoftBody2D script `remove_joint` function, which changes weights for both bones to no longer have weights in other voronoi region.

![Before Break](docs/before-break.png)
![After Break](docs/after-break.png)

That's it. Because of the way the bones weights are built, they have overalapping points that just need to be removed when joint is broken. Easy!

## Credits

Uses parts of code from (godot-chunked-voronoi-generator)[https://github.com/arcanewright/godot-chunked-voronoi-generator]
