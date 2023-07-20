# Changelog

## [v1.1](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v1.1)

- Fix center calculation
- Add square as shape type
- Fix look_at_center if it's connected to only 2 shapes

## [v1.0](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v1.0)

- Add soft_on_inside propert. This makes them look more squishy.
- Add look_at_center option. This makes them look more natural, if you don't need breakable objects.

## [v0.9](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.9)

- Update documentation.
- Remove video recording from repo so that it has less mb.
- Only export addons folder to asset store.

## [v0.8.1](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.8.1)

- Update some default params in scene.

## [v0.8](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.8)

- Fix issue that occured when breaking softbody and bone wouldn't look in correct direction. Also improved how bones look for direction in general.

## [v0.7](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.7)

- Use also PinJoin2D for joints to obtain more bouncy softbodies. Also let option to generate with old SpringJoint.

## [v0.6](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.6)

- Change how softbodies are generated. Use voronoi for generating polygons, then store polygons for each bone. This is used for cutting softbodies.
- There is now option to cut softbodies, making them breakable. This is done by adding breakable_rigidboy2d.gd script(you can also extend it). Still wip.

## [v0.5](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.5)

- Create just one script, SoftBody2D that you can put on a Polygon2D that generates all nodes below.

## v0.4 - UNRELEASED

- Fix bug where if object is rotated weight generation isn't correct.

## [v0.3](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.3)

- Add more tips on how to get a good simulation
- Fix case where if root object is rotated, generation doesn't work.

## [v0.2](https://github.com/Ughuuu/godot-4-softbody2d/releases/tag/v0.2)

- Fix bug with version 4.0 RC3.
- Add more options, make defaults more stable.
- Add more docs on how to use.

## v0.1 - UNRELEASED

- Initial Release
