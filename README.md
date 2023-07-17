# ![icon](https://raw.githubusercontent.com/Ughuuu/godot-4-softbody2d/main/addons/softbody2d/plugin_icon.png) SoftBody2D

# Introduction

Create 2D SoftBodies from a Texture.

1. Create a SoftBody2D node, add a texture to it.
2. Then click bake.

This will create multiple rigidbodies for each region of the object.

If you want Breakable Softbody2D add RigidbodyScript field to `breakable_rigidbody2d.gd` (done in inspector at SoftBody2D/Rigidbody/Rigidbody Script)
, which you can also extend.

# Features

* Non-Breakable and Breakable softbodies
* Pin Joint or Groove Joint

## How it works

### Polygon

1. Creates edge vertices from texture.

2. Creates multiple voronoi regions with roughly same total size as the edge vertices AABB.

![Voronoi Object](docs/voronoi_object.png)

3. Delete the voronoi regions not inside the polygon.

![Voronoi Cut](docs/voronoi_cut.png)

4. Assigns these polygons to the `Polygon2D.polygon` and `Polygon2D.polygons`.

### Skeleton2D

1. Creates a `Skeleton2D` child.
2. Creates a set of `Bone2D`` nodes of the `Skeleton2D`, each having a voronoi region and assign correct weights to them.

### RigidBody2D

1. Creates a set of `RigidBody2D` nodes, one for each voronoi region.
2. Creates for each `Bone2D` a `Rigidody2D` with a `CollisionShape2D` (with a `CircleShape2D` shape) child, a `RemoteTransform2D` child that targets the `Bone2D` position, and either `DampedSprintJoint2D` or `PinJoint2D` children that connects each other neighbour nodes.


![Soft Body](docs/softbody.png)

## For breakable softbodies

If you assign to each rigidbody a `breakable_rigidbody2d.gd` script(done in inspector at SoftBody2D/Rigidbody/Rigidbody Script)

1. When the joint length is too big, the joints breaks. Then, the script `breakable_rigidbody2d.gd` calls on SoftBody2D script `remove_joint` function, which changes weights for both bones to no longer have weights in other voronoi region.

That's it. Because of the way the bones weights are built, they have overlapping points that just need to be removed when joint is broken. Easy!

## Credits

Uses parts of code from (godot-chunked-voronoi-generator)[https://github.com/arcanewright/godot-chunked-voronoi-generator]
