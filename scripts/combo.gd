class_name Combo
extends RefCounted
## Sistema de puntos por trucos (FSA-165).
## Cada truco suma sus puntos base; el combo se multiplica por el número de trucos
## encadenados sin volver a rodar (aire -> grind -> aire...). Repetir el mismo truco
## en un combo vale la mitad cada vez. Si te caes, se pierde todo el combo.

var tricks: Array[String] = []
var base := 0


func add(trick_name: String, points: int) -> int:
	var reps := tricks.count(trick_name)
	var pts := points >> mini(reps, 4)
	tricks.append(trick_name)
	base += pts
	return pts


func multiplier() -> int:
	return tricks.size()


func total() -> int:
	return base * multiplier()


func active() -> bool:
	return not tricks.is_empty()


func clear() -> void:
	tricks.clear()
	base = 0


## Texto del combo: los últimos trucos unidos con "+".
func label() -> String:
	var shown := tricks.slice(maxi(tricks.size() - 3, 0))
	var text := " + ".join(PackedStringArray(shown))
	if tricks.size() > 3:
		text = "… + " + text
	return text
