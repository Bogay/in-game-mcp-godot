extends RefCounted

signal resources_changed()

## Registered resources: URI -> Object (duck-typed)
var available_resources: Dictionary = {}

## Cached resource manifests list
var cached_manifests: Array = []

const DynamicMCPResourceClass = preload("res://addons/mcp_server/dynamic_mcp_resource.gd")

func register_resource(resource: Object) -> void:
    if not resource:
        push_error("[MCP Resource Registry] Cannot register null resource.")
        return
    if not (resource.has_method("get_uri") or resource.has_method("GetUri")):
        push_error("[MCP Resource Registry] Resource must implement get_uri.")
        return
        
    var uri = _get_duck_uri(resource)
    available_resources[uri] = resource
    _rebuild_manifests()

func unregister_resource(resource: Object) -> void:
    if not resource:
        return
    var uri = _get_duck_uri(resource)
    if available_resources.get(uri) == resource:
        available_resources.erase(uri)
        _rebuild_manifests()

func unregister_uri(uri: String) -> void:
    if available_resources.has(uri):
        available_resources.erase(uri)
        _rebuild_manifests()

func register_dynamic_resource(uri: String, name: String, mime_type: String, desc: String, read_callback: Callable) -> void:
    var dynamic_res = DynamicMCPResourceClass.new(uri, name, mime_type, desc, read_callback)
    available_resources[uri] = dynamic_res
    _rebuild_manifests()

func _rebuild_manifests() -> void:
    cached_manifests.clear()
    for uri in available_resources:
        var res = available_resources[uri]
        cached_manifests.append(_get_duck_manifest(res))
    resources_changed.emit()

func _get_duck_uri(resource: Object) -> String:
    if resource.has_method("get_uri"):
        return resource.get_uri()
    elif resource.has_method("GetUri"):
        return resource.GetUri()
    return ""

func _get_duck_name(resource: Object) -> String:
    if resource.has_method("get_name"):
        return resource.get_name()
    elif resource.has_method("GetName"):
        return resource.GetName()
    return "Unnamed Resource"

func _get_duck_mime_type(resource: Object) -> String:
    if resource.has_method("get_mime_type"):
        return resource.get_mime_type()
    elif resource.has_method("GetMimeType"):
        return resource.GetMimeType()
    return "text/plain"

func _get_duck_description(resource: Object) -> String:
    if resource.has_method("get_description"):
        return resource.get_description()
    elif resource.has_method("GetDescription"):
        return resource.GetDescription()
    return ""

func _get_duck_manifest(resource: Object) -> Dictionary:
    if resource.has_method("to_manifest"):
        return resource.to_manifest()
    elif resource.has_method("ToManifest"):
        return resource.ToManifest()
        
    var manifest = {
        "uri": _get_duck_uri(resource),
        "name": _get_duck_name(resource),
        "mimeType": _get_duck_mime_type(resource)
    }
    var desc = _get_duck_description(resource)
    if desc != "":
        manifest["description"] = desc
    return manifest

func read_duck_resource(resource: Object) -> Dictionary:
    if resource.has_method("read"):
        @warning_ignore("redundant_await")
        return await resource.read()
    elif resource.has_method("Read"):
        @warning_ignore("redundant_await")
        return await resource.Read()
    return { "text": "" }
