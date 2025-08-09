import React from 'react';
import { TouchableOpacity, Text, StyleSheet, ViewStyle } from 'react-native';
import { CustomIcon } from './CustomIcon';

interface CustomFABProps {
  icon: string;
  label?: string;
  onPress: () => void;
  style?: ViewStyle;
  disabled?: boolean;
}

export const CustomFAB: React.FC<CustomFABProps> = ({
  icon,
  label,
  onPress,
  style,
  disabled = false,
}) => {
  return (
    <TouchableOpacity
      style={[
        styles.fab,
        disabled && styles.disabled,
        style,
      ]}
      onPress={onPress}
      disabled={disabled}
      activeOpacity={0.8}
    >
      <CustomIcon name={icon} size={24} color="white" />
      {label && (
        <Text style={styles.label}>{label}</Text>
      )}
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  fab: {
    position: 'absolute',
    bottom: 16,
    right: 16,
    backgroundColor: '#2196F3',
    borderRadius: 28,
    width: 56,
    height: 56,
    justifyContent: 'center',
    alignItems: 'center',
    elevation: 8,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    flexDirection: 'row',
    paddingHorizontal: 16,
  },
  disabled: {
    backgroundColor: '#ccc',
  },
  label: {
    color: 'white',
    fontSize: 14,
    fontWeight: 'bold',
    marginLeft: 8,
  },
}); 