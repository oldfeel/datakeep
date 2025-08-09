import React from 'react';
import { Text, StyleSheet } from 'react-native';

interface CustomIconProps {
  name: string;
  size?: number;
  color?: string;
}

export const CustomIcon: React.FC<CustomIconProps> = ({ 
  name, 
  size = 24, 
  color = '#000' 
}) => {
  const getIconSymbol = (iconName: string) => {
    switch (iconName) {
      case 'plus':
        return '+';
      case 'minus':
        return '−';
      case 'close':
        return '×';
      case 'check':
        return '✓';
      case 'edit':
        return '✎';
      case 'delete':
        return '🗑';
      case 'folder':
        return '📁';
      case 'file':
        return '📄';
      case 'settings':
        return '⚙';
      case 'home':
        return '🏠';
      default:
        return '•';
    }
  };

  return (
    <Text style={[styles.icon, { fontSize: size, color }]}>
      {getIconSymbol(name)}
    </Text>
  );
};

const styles = StyleSheet.create({
  icon: {
    fontWeight: 'bold',
    textAlign: 'center',
  },
}); 