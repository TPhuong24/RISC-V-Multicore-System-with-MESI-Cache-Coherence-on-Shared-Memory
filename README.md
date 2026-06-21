# RISC-V Multicore System with MESI Cache Coherence on Shared Memory

![Project Status](https://img.shields.io/badge/Status-Completed-success)
![Language](https://img.shields.io/badge/Hardware_Language-Verilog%20%7C%20SystemVerilog-blue)

## 📌 Giới thiệu dự án (Introduction)
Dự án này là mã nguồn hiện thực hệ thống vi xử lý đa lõi (Multicore CPU) dựa trên kiến trúc tập lệnh **RISC-V**. Điểm nổi bật của hệ thống là việc tích hợp **Giao thức nhất quán bộ nhớ đệm MESI (Modified, Exclusive, Shared, Invalid)** để quản lý giao tiếp giữa các bộ nhớ đệm nội bộ (Private Cache L1) của từng lõi và bộ nhớ RAM dùng chung (Shared Memory) thông qua hệ thống Bus trung gian.

Việc áp dụng trạng thái **Exclusive (E)** của giao thức MESI giúp hệ thống tối ưu hóa băng thông Bus, giảm thiểu độ trễ khi các lõi thực hiện thao tác Ghi (Write) độc quyền.

## ✨ Tính năng cốt lõi (Key Features)
* **RISC-V Cores:** Tích hợp đa lõi xử lý hoạt động độc lập.
* **MESI Cache Coherence:** Hiện thực đầy đủ FSM (Finite State Machine) của 4 trạng thái M, E, S, I để đảm bảo tính nhất quán dữ liệu.
* **Bus Arbiter:** Bộ phân xử quyền truy cập Bus khi có nhiều lõi cùng yêu cầu truy xuất bộ nhớ.
* **Shared Memory:** Bộ nhớ RAM dùng chung cho toàn hệ thống.

## 📂 Cấu trúc thư mục (Directory Structure)
Dự án được chia thành 2 thư mục chính để tối ưu việc quản lý mã nguồn:

* `rtl/`: Chứa toàn bộ source code thiết kế phần cứng (Verilog/SystemVerilog) có khả năng tổng hợp (synthesizable) bao gồm Core, Cache, Bus và Shared Memory.
* `tb/`: Chứa các file phục vụ mô phỏng (Testbench), file mã máy nạp vào bộ nhớ (`.mem`) và script chạy dạng sóng (`report_wave.do`).

## 🚀 Hướng dẫn chạy mô phỏng (How to Simulate)
Để chạy mô phỏng và kiểm tra dạng sóng của dự án này, bạn cần cài đặt phần mềm mô phỏng (ví dụ: ModelSim / QuestaSim).

1. Mở phần mềm mô phỏng và trỏ đường dẫn (Change Directory) về thư mục `tb/` của dự án.
2. Nạp code mã máy từ các file `core0_test.mem` và `core1_test.mem`.
3. Chạy file script để tự động biên dịch và mở dạng sóng bằng lệnh sau trên cửa sổ Transcript:
   ```tcl
   do report_wave.do
