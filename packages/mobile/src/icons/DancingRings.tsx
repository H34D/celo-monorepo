import variables from '@celo/react-components/styles/variables'
import LottieView from 'lottie-react-native'
import React from 'react'

interface Props {
  width?: number
}

export default class DancingRings extends React.PureComponent<Props> {
  static defaultProps = {
    width: 40,
  }

  render() {
    return (
      <LottieView
        source={require('./dancingRings.json')}
        autoPlay={true}
        loop={false}
        style={{ width: variables.width, height: variables.height * 1.25, zIndex: 0 }}
      />
    )
  }
}
