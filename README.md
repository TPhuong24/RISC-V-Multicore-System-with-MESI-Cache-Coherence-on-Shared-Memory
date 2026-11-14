# Hệ thống hai lõi RISC-V với giao thức MESI

![Trạng thái](https://img.shields.io/badge/Status-Completed-success)
![Ngôn ngữ](https://img.shields.io/badge/RTL-Verilog%20%7C%20SystemVerilog-blue)

## Giới thiệu

Đề tài **Hệ thống hai lõi RISC-V với giao thức nhất quán bộ nhớ đệm MESI** hiện thực một hệ thống xử lý gồm hai lõi RISC-V. Mỗi lõi có ROM lệnh và cache dữ liệu L1 riêng. Giao thức MESI duy trì tính nhất quán giữa hai cache khi các lõi truy cập SRAM dùng chung qua bộ phân xử bus.

## Kiến trúc

- **Hai lõi RISC-V** theo kiến trúc Harvard, mỗi lõi có ROM lệnh 1024 word.
- **Cache dữ liệu L1** ánh xạ trực tiếp, gồm 4 set, mỗi dòng chứa 4 word, sử dụng chính sách write-back.
- **Giao thức MESI** gồm bốn trạng thái Modified, Exclusive, Shared và Invalid. Khi một lõi ghi vào dòng cache ở trạng thái Exclusive, dòng đó chuyển sang Modified mà không cần gửi yêu cầu nâng cấp trên bus.
- **Bộ phân xử bus round-robin** cấp quyền truy cập bus khi hai lõi cùng gửi yêu cầu.
- **SRAM dùng chung** lưu dữ liệu của hệ thống.

## Cấu trúc thư mục

| Thư mục | Nội dung |
| --- | --- |
| `rtl/` | Module `top_multicore`, cache, bộ điều khiển cache, bộ phân xử bus và SRAM dùng chung |
| `rtl/core/` | Mã nguồn lõi RISC-V |
| `tb/` | Testbench, ảnh bộ nhớ `.mem` và script mô phỏng |

## Chạy mô phỏng

Môi trường kiểm thử sử dụng **ModelSim Intel FPGA Edition 18.1**.

1. Mở ModelSim và đặt thư mục làm việc về `tb/`.
2. Chạy hai lệnh sau trong cửa sổ **Transcript**.

   ```tcl
   do run_g0_regression.do
   do run_u1.do
   ```

Testbench tự nạp các ảnh `.mem` tương ứng. Kết quả của từng bài và kết quả tổng hợp được in trong Transcript.

## Kết quả kiểm thử

| Bộ kiểm thử | Kết quả |
| --- | --- |
| Regression hệ thống | 18/18 kết quả kỳ vọng, gồm 17 kiểm tra dương PASS và một kiểm tra âm xác nhận scoreboard phát hiện sai lệch |
| Kiểm thử bộ nhớ và MESI | TC1–TC8, D1–D5, shared memory, bus arbiter và testbench tích hợp đạt kết quả mong đợi |
| R1 | Mỗi lõi hoàn thành 2.000 thao tác đọc/ghi `LW` và `SW` được scoreboard kiểm tra |
| U1 | 6/6 bài PASS, gồm ALU, BRANCH, JAL, JALR, PC32 và MEM |
