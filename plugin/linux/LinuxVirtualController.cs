using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using OpenTabletDriver.Plugin;

namespace PressureMapper.Linux;

public static partial class Io
{
    [LibraryImport("libc", EntryPoint = "ioctl", SetLastError = true)]
    public static partial int Ioctl(int fd, uint request);

    [LibraryImport("libc", EntryPoint = "ioctl", SetLastError = true)]
    public static partial int Ioctl(int fd, uint request, int arg);

    [LibraryImport("libc", EntryPoint = "ioctl", SetLastError = true)]
    public static partial int Ioctl(int fd, uint request, ref UinputSetup setup);

    [LibraryImport("libc", EntryPoint = "ioctl", SetLastError = true)]
    public static partial int Ioctl(int fd, uint request, ref UinputAbsSetup absSetup);

    [LibraryImport("libc", EntryPoint = "open", SetLastError = true, StringMarshalling = StringMarshalling.Utf8)]
    public static partial int Open(string path, int flags);

    [LibraryImport("libc", EntryPoint = "close", SetLastError = true)]
    public static partial int Close(int fd);

    [LibraryImport("libc", EntryPoint = "write", SetLastError = true)]
    public static partial int Write(int fd, ref InputEvent ev, int count);

    [LibraryImport("libc", EntryPoint = "clock_gettime", SetLastError = true)]
    public static partial int ClockGetTime(int clockid, ref TimeSpec tp);
}

[StructLayout(LayoutKind.Sequential)]
public struct InputId
{
    public UInt16 bustype;
    public UInt16 vendor;
    public UInt16 product;
    public UInt16 version;
}

[StructLayout(LayoutKind.Sequential)]
public struct TimeSpec
{
    public long tv_sec;
    public long tv_usec;
}

[StructLayout(LayoutKind.Sequential)]
public struct InputEvent
{
    public TimeSpec time;
    public UInt16 type;
    public UInt16 code;
    public Int32 value;
}

[StructLayout(LayoutKind.Sequential)]
public struct UinputSetup
{
    public const int UINPUT_MAX_NAME_SIZE = 80;
    [InlineArray(UINPUT_MAX_NAME_SIZE)]
    public struct UinputName
    {
        private byte _element0;

        public static implicit operator UinputName(Span<byte> str)
        {
            ArgumentOutOfRangeException.ThrowIfGreaterThan(str.Length, UINPUT_MAX_NAME_SIZE);
            UinputName name = new();
            str.CopyTo(name);
            return name;
        }
    }

    public InputId id;
    public UinputName name;
    public UInt32 ff_effects_max;
}

[StructLayout(LayoutKind.Sequential)]
public struct InputAbsInfo
{
    public Int32 value;
    public Int32 minimum;
    public Int32 maximum;
    public Int32 fuzz = 0;
    public Int32 flat = 0;
    public Int32 resolution = 0;

    public InputAbsInfo()
    {

    }
}

[StructLayout(LayoutKind.Sequential)]
public struct UinputAbsSetup
{
    public UInt16 code;
    public InputAbsInfo absinfo;
}

public class IoWrapper
{
    const int O_WRONLY = 0x1;
    const int O_NONBLOCK = 0x800;

    private int fd;

    private IoWrapper(int file_descriptor)
    {
        fd = file_descriptor;
    }

    public static IoWrapper? Open(string path)
    {
        Log.Debug("PressureMapper", "calling open at " + path.ToString());
        int fd = Io.Open(path, O_NONBLOCK | O_WRONLY);
        Log.Debug("PressureMapper", "file descriptor: " + fd);
        if (fd < 0)
        {
            return null;
        }

        return new IoWrapper(fd);
    }

    public void Close()
    {
        if (fd >= 0)
        {
            Io.Close(fd);
            fd = -1;
        }
    }

    public void Setup(ref UinputSetup setup)
    {
        if (fd >= 0)
        {
            Io.Ioctl(fd, UinputConst.UI_DEV_SETUP, ref setup);
        }
    }

    public void AbsSetup(ref UinputAbsSetup absSetup)
    {
        if (fd >= 0)
        {
            Io.Ioctl(fd, UinputConst.UI_ABS_SETUP, ref absSetup);
        }
    }

    public void Enable()
    {
        if (fd >= 0)
        {
            // Enable events
            Io.Ioctl(fd, UinputConst.UI_SET_EVBIT, InputEventCodes.EV_ABS);
            Io.Ioctl(fd, UinputConst.UI_SET_EVBIT, InputEventCodes.EV_KEY);
            Io.Ioctl(fd, UinputConst.UI_SET_EVBIT, InputEventCodes.EV_SYN);

            // Enable buttons and axes
            // Left thumbstick
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_X);
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_Y);
            // Right trigger
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_RZ);
            // A/B buttons
            Io.Ioctl(fd, UinputConst.UI_SET_KEYBIT, InputEventCodes.BTN_A);
            Io.Ioctl(fd, UinputConst.UI_SET_KEYBIT, InputEventCodes.BTN_B);

            // Enable other Xbox 360 inputs so applications dont disregard it
            // Face buttons
            Io.Ioctl(fd, UinputConst.UI_SET_KEYBIT, InputEventCodes.BTN_X);
            Io.Ioctl(fd, UinputConst.UI_SET_KEYBIT, InputEventCodes.BTN_Y);
            // Thumb buttons
            Io.Ioctl(fd, UinputConst.UI_SET_KEYBIT, InputEventCodes.BTN_THUMBL);
            Io.Ioctl(fd, UinputConst.UI_SET_KEYBIT, InputEventCodes.BTN_THUMBR);
            // Right thumbstick
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_RX);
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_RY);
            // D-pad
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_HAT0X);
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_HAT0Y);
            // Left trigger
            Io.Ioctl(fd, UinputConst.UI_SET_ABSBIT, InputEventCodes.ABS_Z);

        }
    }

    public void CreateDevice()
    {
        if (fd >= 0)
        {
            Io.Ioctl(fd, UinputConst.UI_DEV_CREATE);
        }
    }

    public void DestroyDevice()
    {
        if (fd >= 0)
            Io.Ioctl(fd, UinputConst.UI_DEV_DESTROY);
    }

    public void Emit(ushort ev_type, ushort ev_code, int value)
    {
        TimeSpec tp = new();
        Io.ClockGetTime(0, ref tp);
        InputEvent ev = new()
        {
            type = ev_type,
            code = ev_code,
            value = value
        };
        unsafe
        {
            Io.Write(fd, ref ev, sizeof(InputEvent));
        }
    }

    ~IoWrapper()
    {
        DestroyDevice();
        Close();
    }
}

public class Controller
{
    // We mimic a generic Xbox 360 controller so that applications
    // (notably using SDL) can actually register and map inputs.
    const int MICROSOFT_VENDOR_ID = 0x045e;
    const int XBOX_360_PID = 0x028e;
    const int TR_MIN = byte.MinValue;
    const int TR_MAX = byte.MaxValue;
    const int TH_MIN = short.MinValue;
    const int TH_MAX = short.MaxValue;

    private static readonly string[] UINPUT_PATHS = [
        "/dev/uinput",
        "/dev/input/uinput"
    ];

    private readonly IoWrapper io_wrapper;

    public Controller(string name)
    {
        Log.Debug("PressureMapper", "Initializing virtual controller");
        IoWrapper? wrapper = null;
        foreach (string path in UINPUT_PATHS)
        {
            if ((wrapper = IoWrapper.Open(path)) is not null)
                break;
        }
        if (wrapper is null)
        {
            Log.WriteNotify("PressureMapper", "Failed to open uinput. User might not be added to input group, or uinput module is not loaded.", LogLevel.Error);
            throw new IOException("Failed to open uinput");
        }
        io_wrapper = wrapper!;
        Log.Debug("PressureMapper", "Successfully opened uinput");

        UinputSetup setup = new()
        {
            name = Encoding.UTF8.GetBytes(name).AsSpan(),
            id = new InputId
            {
                bustype = 0x03,
                vendor = MICROSOFT_VENDOR_ID,
                product = XBOX_360_PID,
                version = 1
            }
        };

        UinputAbsSetup rTrigger = new()
        {
            code = InputEventCodes.ABS_RZ,
        };
        rTrigger.absinfo.minimum = TR_MIN;
        rTrigger.absinfo.maximum = TR_MAX;

        UinputAbsSetup lThumbX = new()
        {
            code = InputEventCodes.ABS_X,
        };
        lThumbX.absinfo.minimum = TH_MIN;
        lThumbX.absinfo.maximum = TH_MAX;

        UinputAbsSetup lThumbY = new()
        {
            code = InputEventCodes.ABS_Y,
        };
        lThumbY.absinfo.minimum = TH_MIN;
        lThumbY.absinfo.maximum = TH_MAX;

        io_wrapper.Enable();

        io_wrapper.AbsSetup(ref rTrigger);
        io_wrapper.AbsSetup(ref lThumbX);
        io_wrapper.AbsSetup(ref lThumbY);

        io_wrapper.Setup(ref setup);
        io_wrapper.CreateDevice();
        Log.Debug("PressureMapper", "Created uinput device");
    }

    // Minimal actions needed for the plugin

    public void ToggleButton(ControllerButton button, bool toggle)
    {
        ushort code = button switch
        {
            ControllerButton.A => InputEventCodes.BTN_A,
            ControllerButton.B => InputEventCodes.BTN_B,
            _ => 0
        };
        if (code == 0)
            return;

        io_wrapper.Emit(InputEventCodes.EV_KEY, code, toggle ? 1 : 0);
    }

    public void SetLeftThumbstick(Vector2 pos, float max)
    {
        io_wrapper.Emit(InputEventCodes.EV_ABS, InputEventCodes.ABS_X, (int)(TH_MAX * pos.X / max));
        io_wrapper.Emit(InputEventCodes.EV_ABS, InputEventCodes.ABS_Y, (int)(TH_MAX * pos.Y / max));
    }

    public void SetRightTrigger(float percent)
    {
        io_wrapper.Emit(InputEventCodes.EV_ABS, InputEventCodes.ABS_RZ, (int)double.Lerp(TR_MIN, TR_MAX, percent));
    }

    public void Report()
    {
        io_wrapper.Emit(InputEventCodes.EV_SYN, InputEventCodes.SYN_REPORT, 0);
    }
}

public class UinputController : IVirtController
{
    private static readonly Controller controller;

    static UinputController()
    {
        controller = new("OTD Pressure Mapper Virtual Gamepad");
    }

    public override void ToggleButton(ControllerButton button, bool toggle)
    {
        base.ToggleButton(button, toggle);
    }

    public override void SetThumbstick(ControllerSide side, Vector2 value, float max)
    {
        if (side is ControllerSide.Left)
        {
            controller.SetLeftThumbstick(value, max);
        }
    }

    public override void SetTrigger(ControllerSide side, float value, float max)
    {
        if (side is ControllerSide.Right)
        {
            controller.SetRightTrigger(value / max);
        }
    }

    public override void Report()
    {
        controller.Report();
    }
}
