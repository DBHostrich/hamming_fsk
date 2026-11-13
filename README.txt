新增：连续分帧、交织纠错、采样 FSK 自主接收版本。
请先阅读 README_STREAM.txt；ModelSim 入口是 compile_stream.do 和 view_stream.do。
当前 Quartus 工程的顶层改为 hamming_fsk_stream_board，输出目录为 advanced_output。
新增版本尚未执行仿真或编译，仿真由用户完成。

下面保留原始版本的使用说明，原始完整快照为 Git 提交 f28a1c8。

1. hamming_fsk_design.vhd：设计源码
2. tb_hamming_fsk_link.vhd：仿真测试平台
ModelSim仿真已通过


Quartus 上板使用 hamming_fsk_board.qpf，板级顶层为 hamming_fsk_board。
工程按课程 V2 实验板（EP4CE75F23C8、60.8 MHz）配置，下载文件在 output_files/hamming_fsk_board.sof。
上电或松开复位后自动检查 128 帧，无需拨码。按丝印编号读取两排 LED（1=亮）：
LED1–8  预期 1011 000 1（无错误）
LED9–16 预期 1011 011 1（翻转码字第 3 位后恢复）
每排前 4 位是 1011 示例的解码结果，接下来的 3 位是综合征，最后一位表示该组全部通过。

以下为内部逻辑 hamming_fsk_link 的接口说明：
reset为高有效同步复位；busy=0时启动，start给1拍；done为完成脉冲。
data_in和error_mask在启动时锁存；done=1时读取本帧结果。
error_mask=0000000：无错误；0000100：翻转码字位置3（下标2）。

这是共时钟、共比特边界的内部数字方波闭环。
尚未包含DAC/ADC、独立接收同步或真实噪声信道。
错误在解调后人为注入；汉明(7,4)只保证单比特纠错。
