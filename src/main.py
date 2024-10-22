from nada_dsl import *
def nada_main():

    def max(a: SecretInteger, b: SecretInteger) -> SecretInteger:
        return (a < b).if_else(b, a)

    party1 = Party(name="Party1")

    my_int1 = SecretInteger(Input(name="my_int1", party=party1))

    my_int2 = SecretInteger(Input(name="my_int2", party=party1))

    my_int3 = SecretInteger(Input(name="my_int3", party=party1))

    new_int = my_int1 + max(my_int2, my_int3)

    return [Output(new_int, "my_output", party1)]
