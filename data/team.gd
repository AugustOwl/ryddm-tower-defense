class_name Team
extends RefCounted
## The sides of the game. Use Team.PLAYER / Team.ENEMY / Team.NEUTRAL. Parameters that hold a side are typed `int`.
## NEUTRAL structures and units (placed in the level editor) are hostile to both PLAYER and ENEMY.

enum { PLAYER, ENEMY, NEUTRAL }
