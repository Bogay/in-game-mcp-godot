extends Node

func get_uri() -> String:
    return "test://unnamed"

func get_name() -> String:
    return "Unnamed Resource"

func get_description() -> String:
    return ""

func get_mime_type() -> String:
    return "text/plain"

func read() -> Dictionary:
    return { "text": "" }

func to_manifest() -> Dictionary:
    var manifest = {
        "uri": get_uri(),
        "name": get_name(),
        "mimeType": get_mime_type()
    }
    var desc = get_description()
    if desc != "":
        manifest["description"] = desc
    return manifest
