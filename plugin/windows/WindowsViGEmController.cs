
using System.Numerics;
using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.Xbox360;

namespace PressureMapper.Windows;

public class VigEmController : IVirtController
{
    readonly private static ViGEmClient client;
    private static IXbox360Controller controller;

    static VigEmController()
    {
        client = new();
        controller = client.CreateXbox360Controller();
        controller.AutoSubmitReport = false;
        controller.Connect();
    }

    public override void ToggleButton(ControllerButton button, bool toggle)
    {
        Xbox360Button b = button switch
        {
            ControllerButton.A => Xbox360Button.A,
            ControllerButton.B => Xbox360Button.B,
            _ => throw new ArgumentOutOfRangeException(nameof(button))
        };

        controller.SetButtonState(b, toggle);
    }

    public override void SetThumbstick(ControllerSide side, Vector2 value, float max)
    {
        var (x, y) = side switch
        {
            ControllerSide.Left => (Xbox360Axis.LeftThumbX, Xbox360Axis.LeftThumbY),
            _ => (Xbox360Axis.RightThumbX, Xbox360Axis.RightThumbY)
        };

        controller.SetAxisValue(x, (short)(value.X / max * short.MaxValue));
        controller.SetAxisValue(y, (short)(value.X / max * short.MaxValue));
    }

    public override void SetTrigger(ControllerSide side, float value, float max)
    {
        Xbox360Slider slider = side switch
        {
            ControllerSide.Left => Xbox360Slider.LeftTrigger,
            _ => Xbox360Slider.RightTrigger
        };

        controller.SetSliderValue(slider, (byte)(value / max * byte.MaxValue));
    }

    public override void Report()
    {
        controller.SubmitReport();
    }
}