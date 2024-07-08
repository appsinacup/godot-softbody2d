<p align="center">
<img src="https://github.com/appsinacup/godot-softbody2d/blob/main/softbody2d_banner.jpg?raw=true"/>
</p>
<p align="center">
		<img src="https://img.shields.io/badge/Godot-4.2-%23478cbf?logo=godot-engine&logoColor=white" />
</p>

<p align = "center">
	<strong>
		<a href="http://softbody2d.appsinacup.com">Documentation</a> | <a href="https://discord.gg/56dMud8HYn">Discord</a>
	</strong>
</p>


-----

<p align = "center">
<b>2D squishy softbodies</b>
<i>for the Godot game engine.</i>
</p>

-----

Adds the SoftBody2D node which creates a set of RigidBody2Ds and Joint2Ds used with a Skeleton2D in order to deform the texture.

<img src="docs/godot_softbody.gif"/>
</p>

# Installation

- Automatic (Recommended): Download the plugin from the official [Godot Asset Store](https://godotengine.org/asset-library/asset/1621) using the `AssetLib` tab in Godot.
- Manual: Download the source code and move only the addons folder into your project addons folder.

# Features

You can create multiple types of softbodies with this plugin, such as:

- Bouncy SoftBody2D
- Breakable/Deformable SoftBody2D
- SoftBody2D with Hole

# How this plugin creates a softbody

<table>

<tr>
<td>
1. Create polygon from texture around edge.
</td>
<td>
<img width="128px"src="docs/texture_edge.png"/> 
</td>
</tr>

<tr>
<td>
2. Optionally do the same for hole texture.
</td>
<td>
<img width="128px"src="docs/texture_inner.png"/> 
</td>
</tr>

<tr>
<td>
3. Create multiple regions of same size around polygon.
</td>
<td>
<img width="128px"src="docs/texture_regions.png"/> 
</td>
</tr>

<tr>
<td>
4. Delete the regions the polygon or inside the hole polygon.
</td>
<td>
<img width="128px"src="docs/texture_regions_cut.png"/> 
</td>
</tr>

<tr>
<td>
5. Creates a `Skeleton2D` child. Creates a set of `Bone2D` nodes of the `Skeleton2D`, each having a region and assign correct weights to them.
</td>
<td>
<img width="128px"src="docs/skeleton_regions.png"/> 
</td>
</tr>


<tr>
<td>
6. Creates a set of `RigidBody2D` nodes, one for each region with a `CollisionShape2D` child, a `RemoteTransform2D` child that targets the coresponding `Bone2D` position, and a set of `Joint2D` children that connect neighbouring rigidbodies. Also for each `Bone2D` node, make it lookat another neighbour node.
</td>
<td>
<img width="128px"src="docs/softbody_final.png"/> 
</td>
</tr>
<tr>

<td>
7. When the joint length is too big, the joints breaks. Then, the weights for both bones are updated to no longer have weights in the other region.
</td>
<td width=256>
</td>
</tr>
</table>
