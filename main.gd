
extends Node2D

const TOTAL_SLOTS = 8
const ENTRY_POINT = Vector2(85, 265)
const CAR_HALF_SIZE = Vector2(12, 22)
const EXIT_LANE_Y = 265.0
const CAR_TEXTURES: Array[Texture2D] = [
	preload("res://car_textures/car_red.png"),
	preload("res://car_textures/car_blue.png"),
	preload("res://car_textures/car_yellow.png"),
	preload("res://car_textures/car_green.png"),
	preload("res://car_textures/car_purple.png"),
	preload("res://car_textures/car_orange.png"),
	preload("res://car_textures/car_white.png"),
	preload("res://car_textures/car_pink.png")
]

var car_moving = false
var next_car_id = 1
var selected_slot = ""
# Slot name -> occupied state
var occupied = {
	"ParkingSlot1": false,
	"ParkingSlot2": false,
	"ParkingSlot3": false,
	"ParkingSlot4": false,
	"ParkingSlot5": false,
	"ParkingSlot6": false,
	"ParkingSlot7": false,
	"ParkingSlot8": false
}

# Slot name -> car node
var parked_cars: Dictionary = {}

# Parking order: the latest parked car exits first
var parked_order: Array[String] = []

# Waiting car IDs, served in arrival order
var waiting_requests: Array[int] = []

# Per-slot entry timestamps and elapsed-time tracking
var car_entry_times: Dictionary = {}
var car_start_ticks: Dictionary = {}

var parking_history: Array[String] = []


func _ready():
	for slot_name in occupied:
		var slot = get_node(slot_name)
		slot.gui_input.connect(_on_slot_clicked.bind(slot_name))
	# The original Car is used as a hidden template.
	$Car.visible = false

	for slot_name in occupied:
		occupied[slot_name] = false
		get_node(slot_name).color = Color(0.0, 0.65, 0.08)

	$FindParkingButton.pressed.connect(_on_find_parking_pressed)
	$ReleaseParkingButton.pressed.connect(_on_release_parking_pressed)

	load_parking_history()
	update_status()
	update_queue_display()
	update_history_display()

	set_current_status("System ready. Find a parking space.")


func update_status():
	var available = 0

	for slot_name in occupied:
		if not occupied[slot_name]:
			available += 1

	var used = TOTAL_SLOTS - available
	var percentage = int(round(float(used) / TOTAL_SLOTS * 100.0))

	$StatusLabel.text = "Available Slots: %d / %d" % [
		available, TOTAL_SLOTS
	]

	$SystemStatusPanel/PanelInfo.text = "Total Slots: %d" % TOTAL_SLOTS
	$SystemStatusPanel/AvailabilityInfo.text = "Available: %d" % available
	$SystemStatusPanel/OccupiedInfo.text = "Occupied: %d (%d%%)" % [
		used, percentage
	]

	if available == TOTAL_SLOTS:
		$SystemStatusPanel/ParkingStatusInfo.text = "Status: AVAILABLE"
	elif available == 0:
		$SystemStatusPanel/ParkingStatusInfo.text = "Status: FULL"
	else:
		$SystemStatusPanel/ParkingStatusInfo.text = "Status: SPACES LEFT"


func update_queue_display():
	$QueueLabel.text = "QUEUE: %d" % waiting_requests.size()


func set_current_status(message: String):
	$CurrentStatusLabel.text = "CURRENT STATUS\n" + message


func create_car(car_id: int) -> Sprite2D:
	var new_car = $Car.duplicate() as Sprite2D
	new_car.name = "Car_%d" % car_id
	new_car.texture = CAR_TEXTURES[(car_id - 1) % CAR_TEXTURES.size()]

	add_child(new_car)

	new_car.visible = true
	new_car.rotation = PI / 2
	new_car.position = ENTRY_POINT - CAR_HALF_SIZE
	new_car.z_index = 5

	return new_car




func find_nearest_available_slot() -> String:
	var nearest_slot = ""
	var nearest_distance = INF

	for slot_name in occupied:
		if not occupied[slot_name]:
			var slot = get_node(slot_name)
			var center = slot.position + slot.size / 2

			var distance = (
				abs(center.x - ENTRY_POINT.x)
				+ abs(center.y - ENTRY_POINT.y)
			)

			if distance < nearest_distance:
				nearest_distance = distance
				nearest_slot = slot_name

	return nearest_slot


func _on_find_parking_pressed():
	if car_moving:
		return

	var nearest_slot = find_nearest_available_slot()

	# If full, add a new request to the waiting queue.
	if nearest_slot == "":
		waiting_requests.append(next_car_id)
		next_car_id += 1

		update_queue_display()
		update_status()

		$GuidancePath.visible = false
		$StatusLabel.text = "Parking full! Car added to queue."
		set_current_status("Parking full. Car is waiting in the queue.")
		return

	var car_id = next_car_id
	next_car_id += 1

	var new_car = create_car(car_id)
	await park_car_in_slot(new_car, nearest_slot)


func park_car_in_slot(car: Sprite2D, slot_name: String):
	if car_moving:
		return

	car_moving = true

	var slot = get_node(slot_name)
	var slot_center = slot.position + slot.size / 2
	var display_name = slot_name.replace("ParkingSlot", "P")

	# Reserve the slot while the car is moving into it.
	occupied[slot_name] = true
	slot.color = Color(1.0, 0.75, 0.0)

	update_status()

	$StatusLabel.text = "Recommended Parking: " + display_name
	set_current_status("Car is being guided to " + display_name)

	$GuidancePath.points = PackedVector2Array([
		ENTRY_POINT,
		Vector2(slot_center.x, ENTRY_POINT.y),
		slot_center
	])
	$GuidancePath.visible = false

	
	car.position = ENTRY_POINT
	car.rotation = PI / 2

	var waypoint = Vector2(slot_center.x, ENTRY_POINT.y)
	var final_position = slot_center

	var tween = create_tween()
	tween.tween_property(car, "position", waypoint, 1.5)
	tween.tween_property(car, "rotation", 0.0, 0.4)
	tween.tween_property(car, "position", final_position, 1.0)

	await tween.finished
	car.rotation = 0.0


	# Store this specific car in its assigned slot.
	parked_cars[slot_name] = car
	parked_order.append(slot_name)

	car_entry_times[slot_name] = Time.get_datetime_string_from_system()
	car_start_ticks[slot_name] = Time.get_ticks_msec()

	slot.color = Color(0.85, 0.05, 0.05)

	update_status()
	update_queue_display()

	$StatusLabel.text = "Car Parked at " + display_name
	set_current_status("Car parked at " + display_name)

	# The timer displays the latest active parking session.
	$ParkingTimer.start()
	update_parking_timer_display()

	car_moving = false



func _on_release_parking_pressed():
	if car_moving:
		return

	if parked_order.is_empty():
		$StatusLabel.text = "No Car is Parked!"
		set_current_status("No parked cars to release.")
		return

	if selected_slot == "" or not parked_cars.has(selected_slot):
		$StatusLabel.text = "Select an occupied parking slot first!"
		set_current_status("Click an occupied slot, then release that car.")
		return

	car_moving = true

	var slot_name = selected_slot
	var slot = get_node(slot_name)
	var car = parked_cars[slot_name]

	var slot_center = slot.position + slot.size / 2
	var display_name = slot_name.replace("ParkingSlot", "P")

	var is_top_row = slot.position.y < 200
	var lane_entry_y: float

	if is_top_row:
		lane_entry_y = slot.position.y + slot.size.y
	else:
		lane_entry_y = slot.position.y

	
	

	var lane_position = Vector2(slot_center.x, EXIT_LANE_Y)
	var exit_position = Vector2(900, EXIT_LANE_Y)

	$GuidancePath.visible = false

	$StatusLabel.text = "Car Leaving " + display_name
	set_current_status("Car leaving " + display_name)

# First, turn the car to face right while moving to the lane.
	var tween = create_tween()
	tween.tween_property(car, "position", lane_position, 1.0)
	tween.parallel().tween_property(car, "rotation", PI / 2, 0.4)

# Then drive straight along the exit lane.
	tween.tween_property(car, "position", exit_position, 2.0)

	await tween.finished
	car.rotation = PI / 2

	var elapsed_seconds = int(
		(Time.get_ticks_msec() - int(car_start_ticks[slot_name])) / 1000.0
	)

	var minutes = elapsed_seconds / 60
	var seconds = elapsed_seconds % 60
	var exit_time = Time.get_datetime_string_from_system()

	var history_entry = "%s | Entry: %s | Exit: %s | Duration: %02d:%02d" % [
		display_name,
		car_entry_times[slot_name],
		exit_time,
		minutes,
		seconds
	]

	parking_history.append(history_entry)
	save_parking_history()

	parked_cars.erase(slot_name)
	parked_order.erase(slot_name)
	car_entry_times.erase(slot_name)
	car_start_ticks.erase(slot_name)
	selected_slot = ""

	occupied[slot_name] = false
	slot.color = Color(0.0, 0.65, 0.08)
	car.queue_free()

	$GuidancePath.visible = false

	update_status()
	update_history_display()

	$StatusLabel.text = "Car Exited Successfully"
	set_current_status("Car exited successfully.")

	if not waiting_requests.is_empty():
		var queued_car_id = waiting_requests.pop_front()
		update_queue_display()

		var queued_car = create_car(queued_car_id)
		car_moving = false
		await park_car_in_slot(queued_car, slot_name)
		return

	update_queue_display()

	if parked_order.is_empty():
		$ParkingTimer.stop()
		$ParkingTimerLabel.text = "Parking Time: 00:00"
	else:
		update_parking_timer_display()

	car_moving = false









func _on_parking_timer_timeout():
	update_parking_timer_display()


func update_parking_timer_display():
	if parked_order.is_empty():
		$ParkingTimerLabel.text = "Parking Time: 00:00"
		return

	var latest_slot = parked_order[parked_order.size() - 1]

	if not car_start_ticks.has(latest_slot):
		return

	var elapsed = int(
		(Time.get_ticks_msec() - int(car_start_ticks[latest_slot])) / 1000.0
	)

	var minutes = elapsed / 60
	var seconds = elapsed % 60

	$ParkingTimerLabel.text = "Parking Time: %02d:%02d" % [
		minutes, seconds
	]


func save_parking_history():
	var file = FileAccess.open(
		"user://parking_history.txt",
		FileAccess.WRITE
	)

	if file != null:
		for entry in parking_history:
			file.store_line(entry)

		file.close()

	update_history_display()


func load_parking_history():
	parking_history.clear()

	var path = "user://parking_history.txt"

	if not FileAccess.file_exists(path):
		return

	var file = FileAccess.open(path, FileAccess.READ)

	if file != null:
		while file.get_position() < file.get_length():
			var entry = file.get_line()

			if entry.strip_edges() != "":
				parking_history.append(entry)

		file.close()


func update_history_display():
	var history_text = "PARKING HISTORY\n"
	var start_index = max(0, parking_history.size() - 3)

	if parking_history.is_empty():
		history_text += "No parking records yet."
	else:
		for i in range(start_index, parking_history.size()):
			history_text += parking_history[i] + "\n"

	$ParkingHistoryLabel.text = history_text

func _on_slot_clicked(event, slot_name):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if car_moving:
				return

			if not occupied[slot_name]:
				$StatusLabel.text = "This slot is empty."
				return

			selected_slot = slot_name
			var display_name = slot_name.replace("ParkingSlot", "P")

			$StatusLabel.text = "Selected car: " + display_name
			set_current_status("Selected " + display_name + " for release.")
