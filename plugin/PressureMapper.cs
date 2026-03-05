using System.Numerics;
using OpenTabletDriver.Plugin;
using OpenTabletDriver.Plugin.Attributes;
using OpenTabletDriver.Plugin.Output;
using OpenTabletDriver.Plugin.Tablet;

#if WINDOWS
using PressureMapper.Windows;
#elif LINUX
using PressureMapper.Linux;
#endif

namespace PressureMapper;

public enum ControllerButton
{
    A,
    B,
}

public enum ControllerSide
{
    Left,
    Right,
}

public class IVirtController
{
    public virtual void ToggleButton(ControllerButton button, bool toggle) { }
    public virtual void SetThumbstick(ControllerSide side, Vector2 value, float max) { }
    public virtual void SetTrigger(ControllerSide side, float value, float max) { }
    public virtual void Report() { }
}

[PluginName("Pen to Controller Mapper")]
public class ControllerMapper : IPositionedPipelineElement<IDeviceReport>
{
    private uint maxPressure = 4096;
    private readonly static IVirtController controller;

    static ControllerMapper()
    {
#if WINDOWS
        controller = new VigEmController();
#elif LINUX
        controller = new UinputController();
#else
        controller = new IVirtController();
        Log.WriteNotify("PressureMapper", "No virtual controller implementation is available for the current device.", LogLevel.Warning);
#endif
    }

    [TabletReference]
    public TabletReference TabletReference
    {
        set => maxPressure = value.Properties.Specifications.Pen.MaxPressure;
    }


    [Property("Enable Tilt"), DefaultPropertyValue(false)]
    public bool EnableTilt { set; get; }

    [Property("Maximum Tilt"), DefaultPropertyValue(60.0f)]
    public float MaxTilt { set; get; }

    public PipelinePosition Position => PipelinePosition.PostTransform;
    public event Action<IDeviceReport>? Emit;
    public void Consume(IDeviceReport device_report)
    {
        if (device_report is ITabletReport tablet)
        {
            controller.SetTrigger(ControllerSide.Right, tablet.Pressure, maxPressure);
            controller.ToggleButton(ControllerButton.A, tablet.PenButtons[0]);
            controller.ToggleButton(ControllerButton.B, tablet.PenButtons[1]);
        }
        if (EnableTilt && device_report is ITiltReport tilt)
        {
            controller.SetThumbstick(ControllerSide.Left, new Vector2(tilt.Tilt.X, tilt.Tilt.Y), MaxTilt);
        }
        if (device_report is OutOfRangeReport)
        {
            controller.SetTrigger(ControllerSide.Right, 0, maxPressure);
            controller.ToggleButton(ControllerButton.A, false);
            controller.ToggleButton(ControllerButton.B, false);
            controller.SetThumbstick(ControllerSide.Left, Vector2.Zero, short.MaxValue);
        }

        controller.Report();
        Emit?.Invoke(device_report);
    }
}
