import React from 'react';
import { StyleSheet } from 'react-native';
import { Searchbar } from 'react-native-paper';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
  height?: number;
  fontSize?: number;
  onClear?: () => void;
}

export const SearchBar: React.FC<SearchBarProps> = ({
  value,
  onChangeText,
  placeholder = '搜索...',
  height = 48,
  fontSize = 16,
  onClear,
}) => {
  return (
    <Searchbar
      placeholder={placeholder}
      onChangeText={onChangeText}
      value={value}
      onClearIconPress={onClear}
      style={[
        styles.searchBar,
        {
          height,
        },
      ]}
      inputStyle={[
        styles.input,
        {
          fontSize,
        },
      ]}
    />
  );
};

const styles = StyleSheet.create({
  searchBar: {
    marginHorizontal: 16,
    marginVertical: 8,
    borderRadius: 24,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 1,
    },
    shadowOpacity: 0.22,
    shadowRadius: 2.22,
  },
  input: {
    paddingVertical: 0,
  },
}); 