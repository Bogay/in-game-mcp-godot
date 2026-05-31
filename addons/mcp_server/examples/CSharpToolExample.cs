using Godot;
using Godot.Collections;

namespace MCPServer.Examples;

/// <summary>
/// A Decoupled C# MCP Tool example.
/// Because of the duck-typing design, this node does not need to inherit from a specific GDScript class.
/// The MCPServer detects C# style PascalCase method names automatically.
/// </summary>
public partial class CSharpToolExample : Node
{
    public string GetToolName()
    {
        return "csharp_get_system_info";
    }

    public string GetDescription()
    {
        return "Returns details about the host OS and environment configuration using Godot's C# API.";
    }

    public Dictionary GetInputSchema()
    {
        // Must use Godot.Collections.Dictionary and Godot.Collections.Array exclusively.
        // Generic C# collections (System.Collections.Generic.Dictionary) are incompatible with the engine's Variant layer.
        return new Dictionary
        {
            { "type", "object" },
            { "properties", new Dictionary
                {
                    { "verbose", new Dictionary { 
                        { "type", "boolean" }, 
                        { "description", "If true, logs extended locale information" } 
                    } }
                }
            },
            { "required", new Array() }
        };
    }

    public Dictionary Execute(Dictionary args)
    {
        bool verbose = args.ContainsKey("verbose") && args["verbose"].AsBool();
        
        var details = new Dictionary
        {
            { "os_name", OS.GetName() },
            { "locale", OS.GetLocale() },
            { "processor_count", OS.GetProcessorCount() },
            { "is_debug", OS.IsDebugBuild() }
        };
        
        if (verbose)
        {
            details["locale_feedback"] = OS.GetLocaleFocus();
            details["model_name"] = OS.GetModelName();
        }

        var content = new Array
        {
            new Dictionary
            {
                { "type", "text" },
                { "text", Json.SchemaStringify(details) }
            }
        };

        return new Dictionary
        {
            { "isError", false },
            { "content", content }
        };
    }
}
