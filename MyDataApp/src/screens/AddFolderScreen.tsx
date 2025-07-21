import React, { useState } from 'react';
import { View, StyleSheet, Text } from 'react-native';
import { Appbar, TextInput, Checkbox, Button } from 'react-native-paper';
import { Picker } from '@react-native-picker/picker';

const mockDevices = [
    { id: 'local', name: '本机' },
    { id: 'pc', name: '电脑' },
    { id: 'tv', name: '电视' },
];

export default function AddFolderScreen({ navigation }: any) {
    const [folder, setFolder] = useState({
        label: '',
        path: '',
        type: 'sendreceive',
        paused: false,
        shared: ['local'],
    });

    // 模拟文件夹选择
    const handleSelectFolder = async () => {
        setFolder({ ...folder, path: '/storage/emulated/0/DCIM' });
    };

    const handleToggleShare = (id: string) => {
        const shared = folder.shared || [];
        setFolder({
            ...folder,
            shared: shared.includes(id)
                ? shared.filter(d => d !== id)
                : [...shared, id],
        });
    };

    return (
        <View style={styles.container}>
            <View style={styles.form}>
                <TextInput
                    label="文件夹名称"
                    value={folder.label}
                    onChangeText={label => setFolder({ ...folder, label })}
                    style={styles.input}
                />
                <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <TextInput
                        label="文件夹路径"
                        value={folder.path}
                        editable={false}
                        style={[styles.input, { flex: 1 }]}
                    />
                    <Button mode="outlined" onPress={handleSelectFolder} style={{ marginLeft: 8, marginBottom: 12 }}>
                        选择
                    </Button>
                </View>
                <View style={styles.rowAlign}>
                    <Text style={styles.syncTypeLabel}>同步类型</Text>
                    <View style={styles.pickerWrapper}>
                        <Picker
                            selectedValue={folder.type}
                            onValueChange={type => setFolder({ ...folder, type })}
                            style={styles.picker}
                            itemStyle={{ fontSize: 16 }}
                        >
                            <Picker.Item label="发送和接收" value="sendreceive" />
                            <Picker.Item label="仅发送" value="sendonly" />
                            <Picker.Item label="仅接收" value="receiveonly" />
                        </Picker>
                    </View>
                </View>
                <Checkbox.Item
                    label="暂停同步"
                    status={folder.paused ? 'checked' : 'unchecked'}
                    onPress={() => setFolder({ ...folder, paused: !folder.paused })}
                />
                <Text style={styles.shareTitle}>共享设备</Text>
                {mockDevices.map(dev => (
                    <Checkbox.Item
                        key={dev.id}
                        label={dev.name}
                        status={folder.shared?.includes(dev.id) ? 'checked' : 'unchecked'}
                        onPress={() => handleToggleShare(dev.id)}
                    />
                ))}
                <Button mode="contained" onPress={() => {
                    // 保存逻辑
                    navigation.goBack();
                }} style={styles.saveBtn}>
                    保存
                </Button>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#fff' },
    form: { padding: 16 },
    input: { marginBottom: 12 },
    saveBtn: { marginTop: 24 },
    shareTitle: { marginTop: 16, fontWeight: 'bold', fontSize: 16, marginBottom: 4 },
    pickerWrapper: { borderWidth: 1, borderColor: '#ccc', borderRadius: 6, marginBottom: 12, flex: 1 },
    picker: { width: '100%' },
    rowAlign: { flexDirection: 'row', alignItems: 'center', marginBottom: 12 },
    syncTypeLabel: { color: '#888', fontSize: 16, marginRight: 12, width: 80 },
}); 