using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.Xbox360;
using OpenTabletDriver.Plugin.Attributes;
using OpenTabletDriver.Plugin.Output;
using OpenTabletDriver.Plugin.Tablet;

namespace pressure_mapper;

[PluginName("Pen to Controller Mapper")]
public class ControllerMapper : IPositionedPipelineElement<IDeviceReport>
{
    readonly private static ViGEmClient client;
    private static IXbox360Controller controller;
    private uint maxPressure = 4096;
    static ControllerMapper()
    {
        client = new();
        controller = client.CreateXbox360Controller();
        controller.AutoSubmitReport = false;
        controller.Connect();
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
            var ratio = (float)tablet.Pressure / (float)maxPressure;
            controller.SetSliderValue(Xbox360Slider.RightTrigger, (byte)(ratio * 255.0f));
            controller.SetButtonState(Xbox360Button.A, tablet.PenButtons[0]);
            controller.SetButtonState(Xbox360Button.B, tablet.PenButtons[1]);
        }
        if (EnableTilt && device_report is ITiltReport tilt)
        {
            controller.SetAxisValue(Xbox360Axis.LeftThumbX, (short)(tilt.Tilt.X / MaxTilt * short.MaxValue));
            controller.SetAxisValue(Xbox360Axis.LeftThumbY, (short)(tilt.Tilt.Y / MaxTilt * short.MaxValue));
        }
        if (device_report is OutOfRangeReport)
        {
            controller.SetSliderValue(Xbox360Slider.RightTrigger, 0);
            controller.SetButtonState(Xbox360Button.A, false);
            controller.SetButtonState(Xbox360Button.B, false);
            controller.SetAxisValue(Xbox360Axis.LeftThumbX, 0);
            controller.SetAxisValue(Xbox360Axis.LeftThumbY, 0);
        }

        controller.SubmitReport();
        Emit?.Invoke(device_report);
    }
}
